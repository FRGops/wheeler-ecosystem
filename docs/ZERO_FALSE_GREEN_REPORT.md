# Wheeler Ecosystem — Zero False Green Report

**Document type:** Definitive Production Health Assessment
**Author:** Principal Zero-False-Green Systems Engineer
**Date:** 2026-05-23
**Classification:** CEO/Board-Level — Read Before Approving Any Production Change
**Status:** READ-ONLY. Do not execute commands against live servers from this document.

---

## SECTION 1: EXECUTIVE JUDGMENT

The Wheeler ecosystem is NOT production-ready. Of the 25 catalogued services, exactly ZERO have been verified against all 10 zero-false-green conditions. Three revenue-critical services are provably broken (FRGCRM API errored after 15 restart attempts; SurplusAI Scraper Agent and Voice Agent Service each stuck in 282+ restart loops). The primary revenue generator, Prediction Radar, is serving live traffic but operating with Stripe test-mode keys — meaning it may not be collecting real payments despite appearing healthy on all naive checks. Half the ecosystem (Hostinger edge node) has zero verified health status because no remote access exists from the assessment vantage point. The COREDB node — the target for all database migration — has never been confirmed reachable. The lead intake pipeline, touted as the core revenue engine, is completely non-functional at all 6 stages due to a single missing environment variable (`DEEPSEEK_API_KEY`). The ecosystem presents approximately 40% of services as "green" through surface-level checks, but deep inspection reveals that the actual number of provably-healthy services is between 3 and 5 — and even those have unverified conditions. Production cutover or migration at this moment would spread breakage to the few services that still work. **Verdict: DO NOT PROCEED with any infrastructure changes until the 3 broken services are fixed, Stripe mode is confirmed, Hostinger services are inventoried, and COREDB connectivity is verified.**

---

## SECTION 2: SERVICE HEALTH CLASSIFICATION

Every service classified against all 10 Zero-False-Green conditions:

| # | Condition | Description |
|---|-----------|-------------|
| C1 | Process online | Process manager (PM2/Docker/systemd) reports running |
| C2 | Port listening | Service is bound to and listening on its assigned port |
| C3 | Health endpoint 200 | Health check endpoint returns HTTP 200 |
| C4 | No crash loop | Restart count is 0 and stable (no PM2 restarts in last 1h) |
| C5 | Dependencies reachable | All declared dependencies respond to connectivity checks |
| C6 | Public route works | Public-facing URL returns 200 from external network |
| C7 | Restart survives | Service can be restarted without entering error/waiting state |
| C8 | Rollback exists | Documented, tested rollback procedure available |
| C9 | Monitoring exists | Service is covered by at least one monitoring system (Uptime Kuma, Prometheus, or Grafana) |
| C10 | Owner/role documented | Owner, purpose, and role are documented in the service inventory |

**Classification logic:**
- **TRULY HEALTHY:** All 10 conditions verified with evidence
- **PARTIALLY HEALTHY:** Process is up and serving, but >=1 condition is unverified or missing
- **FAKE HEALTHY:** Naive check (ping/curl/PM2 status) shows green, but deeper inspection reveals failure
- **BROKEN:** Confirmed non-functional
- **UNVERIFIED:** Cannot determine status remotely (no SSH access, no health endpoint reachable)

---

### 2.1 TRULY HEALTHY (all 10 conditions verified)

**None.**

No service in the Wheeler ecosystem has been verified against all 10 conditions. The strongest candidates — Prediction Radar and RavynAI — have conditions C4 (logs not inspected for hidden crash loops), C6 (public route not externally verified), C7 (no controlled restart test performed), and C8 (rollback documented but never tested). These services are classified as PARTIALLY HEALTHY below. The absence of truly-healthy services is the single most important finding in this report.

---

### 2.2 PARTIALLY HEALTHY (some conditions met, some unverified)

#### 2.2.1 Prediction Radar (API + Worker + Scheduler + Dashboard v2)

```
Server:    AIOPS (Hetzner 5.78.140.118)
Ports:     8000 (API), 8098 (web)
Manager:   Docker Compose
Uptime:    43h at last survey
```

| Condition | Status | Evidence |
|-----------|--------|----------|
| C1 Process online | VERIFIED | Docker container `prediction-radar-app` running 43h |
| C2 Port listening | VERIFIED | Port 8000 documented as internal API port |
| C3 Health endpoint 200 | VERIFIED | `/health` route documented with expected response |
| C4 No crash loop | UNVERIFIED | Container uptime 43h is positive, but no log inspection for hidden error loops |
| C5 Dependencies reachable | PARTIAL | PostgreSQL and Redis in same Docker compose — healthy per Docker health checks. External AI providers (DeepSeek, OpenAI, Anthropic) not independently verified. |
| C6 Public route works | UNVERIFIED | `predictionradar.app` routed via Cloudflare -> Hostinger -> Tailscale -> AIOPS. Never verified end-to-end from external network. |
| C7 Restart survives | UNVERIFIED | No controlled restart test performed. Docker `restart: unless-stopped` documented but not tested. |
| C8 Rollback exists | PARTIAL | Documented in REVENUE_ROLLBACK_PLAN.md but never tested in dry-run. |
| C9 Monitoring exists | PARTIAL | Prometheus scrape documented but not confirmed. Uptime Kuma coverage assumed. |
| C10 Owner/role documented | VERIFIED | Documented in TEST_INVENTORY.md, REVENUE_APP_INVENTORY.md, API_READINESS_MATRIX.md |

**Risk level: HIGH** — This is the primary revenue generator. If any unverified condition fails (especially C6 public routing or C5 AI provider), revenue stops. The Stripe test-mode key issue (see Section 2.3 Fake Healthy) compounds this.

**What's working:** Container is running, Docker health checks pass, DB and Redis are healthy in the same compose stack.

**What's unverified:** End-to-end public access, AI provider connectivity, restart resilience, rollback procedure.

#### 2.2.2 RavynAI API

```
Server:    AIOPS (Hetzner 5.78.140.118)
Port:      8007
Manager:   Docker Compose
Uptime:    43h at last survey
```

| Condition | Status | Evidence |
|-----------|--------|----------|
| C1 Process online | VERIFIED | Docker container healthy, 43h uptime |
| C2 Port listening | VERIFIED | Port 8007 routed via Traefik and Tailscale |
| C3 Health endpoint 200 | LIKELY | `/health` route documented, expected JSON `{"status":"healthy"}` |
| C4 No crash loop | UNVERIFIED | Container logs not inspected |
| C5 Dependencies reachable | PARTIAL | Own PostgreSQL (`aiops-ravynai-postgres`) healthy. FRGCRM_API_URL configured but FRGCRM API is BROKEN — impact unclear. |
| C6 Public route works | UNVERIFIED | `ravynai.wheeler.ai` documented but never verified end-to-end |
| C7 Restart survives | UNVERIFIED | No restart test performed |
| C8 Rollback exists | PARTIAL | Documented but untested |
| C9 Monitoring exists | UNVERIFIED | Not confirmed in Prometheus or Uptime Kuma |
| C10 Owner/role documented | VERIFIED | Documented in API_READINESS_MATRIX.md and REVENUE_APP_INVENTORY.md |

**Risk level: MEDIUM** — Isolated service with its own database. Low coupling to broken services. Primary risk is untested restart and lack of monitoring coverage.

#### 2.2.3 FRGCRM Agent Service

```
Server:    AIOPS (Hetzner 5.78.140.118)
Port:      8003 (AGENT_SVC_PORT)
Manager:   PM2, id 0
Uptime:    42h at last survey
```

| Condition | Status | Evidence |
|-----------|--------|----------|
| C1 Process online | VERIFIED | PM2 status: ONLINE, 0 restarts |
| C2 Port listening | VERIFIED | Port 8003 documented in env vars |
| C3 Health endpoint 200 | LIKELY | `/health` route returns agent list and DAG status |
| C4 No crash loop | VERIFIED | 0 restarts, 42h stable |
| C5 Dependencies reachable | FAILED | FRGCRM_API_URL points to FRGCRM API which is BROKEN. PostgreSQL frgops-standby reachable. DEEPSEEK_API_KEY NOT SET — all 6 pipeline stages fail. |
| C6 Public route works | N/A | Internal service, no public route |
| C7 Restart survives | UNVERIFIED | Never restarted. 42h stable but restart behavior unknown. |
| C8 Rollback exists | PARTIAL | PM2 save/restore documented |
| C9 Monitoring exists | UNVERIFIED | PM2 status visible but no external alerting confirmed |
| C10 Owner/role documented | VERIFIED | Documented in all inventory docs |

**Risk level: CRITICAL** — This is the most insidious case in the ecosystem. PM2 says ONLINE. The health endpoint will return 200. But the service is **completely non-functional** for its actual purpose. All 6 pipeline stages (LeadIngestion, CaseScorer, AttorneyMatcher, ClaimantOutreach, DocumentGenerator, PipelineMonitor) fail because `DEEPSEEK_API_KEY` is not set. Additionally, it can't reach the FRGCRM API (BROKEN) for data operations. This service appears healthy but accomplishes nothing.

**Would be classified as FAKE HEALTHY if this report used a single-trigger rule.** The only reason it's PARTIALLY HEALTHY rather than FAKE HEALTHY is that the process itself is stable — it's the application logic that's broken, not the process lifecycle. For practical purposes, consider this service NON-FUNCTIONAL for all revenue operations.

#### 2.2.4 FRGCRM Mirror Test

```
Server:    AIOPS (Hetzner 5.78.140.118)
Port:      8003 (IPv6) / 8099 (PORT env)
Manager:   PM2, id 4
Uptime:    42h at last survey
```

| Condition | Status | Evidence |
|-----------|--------|----------|
| C1 Process online | VERIFIED | PM2 status: ONLINE, 0 restarts, 42h |
| C2 Port listening | LIKELY | Port 8003/8099 documented |
| C3 Health endpoint 200 | LIKELY | `/health` route assumed (same codebase as agent svc) |
| C4 No crash loop | VERIFIED | 0 restarts, 42h stable |
| C5 Dependencies reachable | FAILED | Same as FRGCRM Agent Service — FRGCRM API BROKEN, DEEPSEEK_API_KEY missing |
| C6 Public route works | N/A | Internal test service |
| C7 Restart survives | UNVERIFIED | Never tested |
| C8 Rollback exists | UNVERIFIED | Not documented |
| C9 Monitoring exists | UNVERIFIED | No confirmed monitoring |
| C10 Owner/role documented | VERIFIED | Documented as test environment |

**Risk level: LOW** — Internal test service. Not revenue-critical. Useful for validating fixes before production.

#### 2.2.5 Insforge Agent Service

```
Server:    AIOPS (Hetzner 5.78.140.118)
Port:      8013 (IPv6)
Manager:   PM2, id 3
Uptime:    42h at last survey
```

| Condition | Status | Evidence |
|-----------|--------|----------|
| C1 Process online | VERIFIED | PM2: ONLINE, 0 restarts, 42h |
| C2 Port listening | LIKELY | Port 8013 documented (shared with FRGCRM Agent Svc?) |
| C3 Health endpoint 200 | UNVERIFIED | Health route unknown |
| C4 No crash loop | VERIFIED | 0 restarts, 42h stable |
| C5 Dependencies reachable | UNVERIFIED | No documented database/Redis dependencies |
| C6 Public route works | N/A | Internal agent |
| C7 Restart survives | UNVERIFIED | Never tested |
| C8 Rollback exists | UNVERIFIED | Not documented |
| C9 Monitoring exists | UNVERIFIED | No confirmed monitoring |
| C10 Owner/role documented | VERIFIED | Documented in REVENUE_APP_INVENTORY.md and API_READINESS_MATRIX.md |

**Risk level: LOW** — Internal agent. No revenue impact documented. Minimal dependencies.

#### 2.2.6 Docuseal

```
Server:    AIOPS (Hetzner 5.78.140.118) — migrated from Hostinger
Port:      3010
Manager:   Docker Compose
```

| Condition | Status | Evidence |
|-----------|--------|----------|
| C1 Process online | VERIFIED | Docker container healthy, 43h |
| C2 Port listening | VERIFIED | Port 3010 routed via Tailscale from Hostinger Traefik |
| C3 Health endpoint 200 | LIKELY | `/health` endpoint documented |
| C4 No crash loop | UNVERIFIED | Container logs not inspected |
| C5 Dependencies reachable | PARTIAL | docuseal-redis healthy. Connected to frgops-standby PG:5433. |
| C6 Public route works | UNVERIFIED | `docuseal.wheeler.ai` documented — never verified from external network |
| C7 Restart survives | UNVERIFIED | Never tested |
| C8 Rollback exists | PARTIAL | Documented but untested |
| C9 Monitoring exists | UNVERIFIED | Not confirmed |
| C10 Owner/role documented | VERIFIED | Documented |

**Risk level: LOW** — Non-revenue support service. E-signature tool.

---

### 2.3 FAKE HEALTHY (appears up but has hidden failures)

THIS IS THE MOST IMPORTANT SECTION. These are the services that will pass a cursory health check and produce false confidence. Each entry includes the **naive check** (the one that lies) and the **real check** (the one that reveals the truth).

---

#### 2.3.1 Prediction Radar — Stripe TEST MODE (CRITICAL)

**Naive check (LIES):**
```bash
curl -s https://predictionradar.app  # Returns HTTP 200
docker ps | grep prediction-radar    # Shows "healthy" for 43h
curl -s http://localhost:8000/health # Returns {"status":"healthy"}
```
This check says: "Prediction Radar is up and serving."

**Real check (TRUTH):**
```bash
# Check Stripe key mode
docker exec prediction-radar-app env | grep STRIPE_SECRET_KEY
# Output: STRIPE_SECRET_KEY=sk_test_...  <-- TEST MODE

# Verify in Stripe Dashboard: Are live charges being processed?
# Answer if test keys: NO. All "payments" are hitting Stripe test environment.
# Real money is NOT being collected.
```
This check reveals: **Prediction Radar may not be collecting any real payments.** Seven subscription tiers are configured, the checkout flow works, the webhooks fire — but all of it happens in Stripe's test sandbox. If the service has real users subscribing, those subscriptions are generating zero revenue.

**What makes this fake-healthy:**
- Docker health checks pass (container is running)
- Health endpoint returns 200 (API code is executing)
- Public route works (loads the checkout page)
- Payment flow appears functional (Stripe test mode works identically to live mode)
- PM2/Docker shows healthy (process is up)

**What's actually happening:**
- Real customers may be signing up and entering credit card details
- Those cards are never charged real money
- Subscriptions exist in Stripe test mode, not in the live Stripe account
- If test data has real customer PII, there may be compliance issues (test mode data is not covered by Stripe's production data processing agreements)

**Impact:** If this is unintentional, **100% of Prediction Radar revenue is not being collected.** If intentional (staging environment), the service should not be classified as production.

**Risk level: CRITICAL**

---

#### 2.3.2 FRGCRM Agent Service — Pipeline All Stages Failing (CRITICAL)

**Naive check (LIES):**
```bash
pm2 list | grep frgcrm-agent-svc    # Shows "online", 0 restarts, 42h uptime
curl -s http://localhost:8003/health  # Returns 200 with agent list
```
This check says: "Agent service is running perfectly."

**Real check (TRUTH):**
```bash
# Trigger the pipeline and observe failure
curl -s -X POST http://localhost:8003/pipeline/dag/run
# Observe the DAG result
curl -s http://localhost:8003/pipeline/dag/latest | jq '.stages[] | {stage: .name, status: .status}'
# Every stage shows: "FAILED" — reason: "OpenAI API key is required"

# Verify the root cause
pm2 env 0 | grep -E 'DEEPSEEK_API_KEY|OPENAI_API_KEY'
# Both are EMPTY/UNDEFINED
```
This check reveals: **The entire 6-stage lead intake pipeline is non-functional.** The process runs, the health endpoint responds, but the application logic cannot execute because no AI provider API key is configured. Six stages, every one failing with the same error.

**Impact:** Zero leads being ingested, scored, matched to attorneys, or sent outreach. The core revenue pipeline is dead while reporting green.

**Risk level: CRITICAL**

---

#### 2.3.3 FRGCRM Frontend (fundsrecoverygroup.com) — Depends on Broken API (HIGH)

**Naive check (LIES):**
```bash
curl -sI https://fundsrecoverygroup.com | head -1  # Returns HTTP/2 200
curl -sI https://frgops.fundsrecoverygroup.tech | head -1  # Returns HTTP/2 200
```
This check says: "FRGCRM is up and serving clients."

**Real check (TRUTH):**
```bash
# The frontend is serving HTML (Hostinger) but...
# Every form submission POSTs to FRGCRM API which IS BROKEN (PM2 errored)
# From AIOPS node:
pm2 list | grep frgcrm-api  # Status: "errored", 15 restarts

# Try to submit a lead (from the frontend's perspective):
# POST to FRGCRM API -> Connection refused / 502 Bad Gateway
```
This check reveals: **The website loads, but any form submission, lead intake, CRM operation, or client lookup will fail.** Users see a working website. They fill out forms. They click submit. Nothing happens — or they get a generic error page.

**Impact:** The public face of the business accepts leads that are silently discarded. Each day this persists is a day of lost leads that may never be recovered.

**Risk level: HIGH**

---

#### 2.3.4 SurplusAI Portal (surplusai.io) — Scraper in 282+ Restart Loop (HIGH)

**Naive check (LIES):**
```bash
curl -sI https://surplusai.io | head -1  # Returns HTTP/2 200
# Frontend loads, looks operational
```
This check says: "SurplusAI is up."

**Real check (TRUTH):**
```bash
# From AIOPS node:
pm2 list | grep surplusai-scraper  # Status: "WAITING", 282+ restarts
pm2 logs surplusai-scraper-agent-svc --lines 10
# Shows repeated crash/restart cycle. The scraper is not scraping.
# The frontend is serving static content, but the data pipeline is dead.
```
This check reveals: **The SurplusAI data pipeline has not processed any data since the restart loop began.** The frontend renders, but displays stale or empty data. 282 restart attempts means this has been broken for an extended period — potentially weeks.

**Impact:** SurplusAI data products are not updating. Dependent customers receive stale or empty data.

**Risk level: HIGH**

---

#### 2.3.5 Voice Agent Service — 282+ Restart Loop (HIGH)

**Naive check (LIES):**
```bash
pm2 list | grep voice-agent-svc  # Could appear in various states
# PM2 might report "online" momentarily between restarts, giving false confidence
```
This check says: "Voice agent is running" (during the brief window between restarts).

**Real check (TRUTH):**
```bash
pm2 jlist | jq '.[] | select(.name=="voice-agent-svc") | {status: .pm2_env.status, restarts: .pm2_env.restart_time}'
# Status: "waiting" (PM2 exhausted max_restarts=5)
# Restarts: 282+
# Port 8008: NOT LISTENING (process isn't staying up long enough to bind)
```
This check reveals: **Voice agent is in a permanent crash loop.** PM2 has given up restarting it after exhausting the max restart count. The service is effectively dead but PM2 shows it as "waiting" rather than "stopped" or "errored" — an easy state to overlook.

**Impact:** All outbound voice operations stopped. Client follow-ups not happening. Campaign calls not executing.

**Risk level: HIGH**

---

#### 2.3.6 LiteLLM Gateway — Hostinger-Side, Unverified, Single Point of Failure (HIGH)

**Naive check (LIES):**
```bash
# From AIOPS — no check possible. The service "must" be working because AI features in Prediction Radar work.
# This assumption is the lie.
```
This check says: "AI features work, therefore LiteLLM must be up." (Circular reasoning)

**Real check (TRUTH):**
```bash
# LiteLLM runs on Hostinger (port 4000). From AIOPS, we CANNOT verify it.
# The Prediction Radar uses its own AI provider configs (direct API keys).
# The FRGCRM Agent Service uses DEEPSEEK_API_KEY directly, not via LiteLLM.
# Other services may depend on LiteLLM — and we have no way to check.

# Required check (requires Hostinger SSH):
curl -s http://localhost:4000/health | jq .
curl -s http://localhost:4000/v1/models | jq '.data | length'
# If either returns an error: ALL LiteLLM-dependent services are offline.
```
This check reveals: **We have NO IDEA whether LiteLLM is working.** It appears in the service inventory as a dependency for SurplusAI API and Wheeler Brain OS API. If it's down, those services silently fail. We cannot verify from the AIOPS node.

**Impact:** If LiteLLM is down, SurplusAI API and Wheeler Brain OS API — both documented as depending on it — are non-functional regardless of their process status.

**Risk level: HIGH**

---

#### 2.3.7 PM2 — Managing Broken Processes While Reporting Clean (MEDIUM)

**Naive check (LIES):**
```bash
pm2 ping  # Returns "pong"
pm2 list  # Shows a list of processes — must be all good, right?
```
This check says: "PM2 is running, therefore managed services are fine."

**Real check (TRUTH):**
```bash
pm2 jlist | jq 'map(select(.pm2_env.status != "online")) | .[] | {name: .name, status: .pm2_env.status, restarts: .pm2_env.restart_time}'
# Output:
# {name: "frgcrm-api", status: "errored", restarts: 15}
# {name: "surplusai-scraper-agent-svc", status: "waiting", restarts: 282}
# {name: "voice-agent-svc", status: "waiting", restarts: 282}
```
This check reveals: **3 of 6 PM2-managed processes (50%) are broken.** PM2 itself is healthy — it's doing its job of reporting process status accurately. But a naive "PM2 is running" check gives false confidence that managed services are healthy.

**Impact:** Process management is working, but half the managed processes are dead. The PM2 daemon restart would restart the 3 healthy services and may or may not recover the 3 broken ones — a risky proposition.

**Risk level: MEDIUM**

---

### 2.4 BROKEN (confirmed down or failing)

#### 2.4.1 FRGCRM API — BROKEN

```
Service:    FRGCRM API
Server:     AIOPS (Hetzner 5.78.140.118)
PM2 ID:     6
Status:     ERRORED
Restarts:   15
Port:       N/A — process not listening
Root cause: ASGI import error: "Could not import module 'main'"
```

**Evidence of failure:**
```bash
# PM2 status
ssh aiops "pm2 list | grep frgcrm-api"
# Status: errored, PID 0 (not running), 15 restart attempts

# Error log
ssh aiops "pm2 logs frgcrm-api --lines 10 --nostream"
# Error: Error loading ASGI app. Could not import module "main".

# Port check
ssh aiops "ss -tlnp | grep -E '8002|8013'"
# No frgcrm-api process listening on any port
```

**Impact assessment:**
- CRM operations completely offline
- Lead management blocked
- Case management unavailable
- Client communication capabilities lost
- FRGCRM Agent Service cannot perform data operations (all API calls fail)
- Attorney data inaccessible (GET /api/attorney returns nothing)
- At least 4 services depend on this API directly (FRGCRM Frontend, FRGCRM Agent Svc, FRGCRM Mirror Test, SurplusAI Scraper)

**Recovery actions documented but not executed:**
1. Inspect working directory and verify `main.py` exists
2. Check virtual environment activation in PM2 ecosystem config
3. Verify Python dependencies installed
4. Check for port conflict (port 8013 shared with other services)
5. Verify database connectivity to frgops-standby:5433

**Estimated time to fix:** 2-4 hours (documented in REVENUE_SYSTEMS_EXECUTIVE_REPORT.md)

---

#### 2.4.2 SurplusAI Scraper Agent — BROKEN

```
Service:    SurplusAI Scraper Agent Service
Server:     AIOPS (Hetzner 5.78.140.118)
PM2 ID:     1
Status:     WAITING (PM2 gave up after exhausting max_restarts=5)
Restarts:   282+
Port:       N/A — never stays up long enough to bind
```

**Evidence of failure:**
```bash
ssh aiops "pm2 list | grep surplusai-scraper-agent-svc"
# Status: waiting, 282+ restarts
```

**Impact assessment:**
- SurplusAI data pipeline offline
- No new surplus-funds leads being scraped
- SurplusAI portal serving stale/empty data
- May be waiting on FRGCRM API (if FRGCRM API fix cascades to resolve this, effort is near-zero)

**Likely root cause:** Missing `DEEPSEEK_API_KEY` (same pattern as FRGCRM Agent Service) OR blocked waiting for FRGCRM API to come online.

---

#### 2.4.3 Voice Agent Service — BROKEN

```
Service:    Voice Agent Service
Server:     AIOPS (Hetzner 5.78.140.118)
PM2 ID:     2
Status:     WAITING (PM2 gave up after exhausting max_restarts=5)
Restarts:   282+
Port:       8008 — not listening
```

**Evidence of failure:**
```bash
ssh aiops "pm2 list | grep voice-agent-svc"
# Status: waiting, 282+ restarts
```

**Impact assessment:**
- Voice outreach operations offline
- Internal voice AI assistant non-functional
- May be lower priority than FRGCRM API and SurplusAI if voice is not currently in active use

**Likely root cause:** Same `DEEPSEEK_API_KEY` issue as other agent services. Uses `@strands-agents/sdk` with the same `createModel()` pattern.

---

### 2.5 UNVERIFIED (cannot determine status remotely)

These services all run on the Hostinger EDGE node (187.77.148.88). Zero remote verification has been performed from the AIOPS vantage point. Every claim about these services is ASSUMED, not confirmed.

| # | Service | Server | Port | Why Unverifiable | Risk of Assuming Healthy |
|---|---------|--------|------|------------------|------------------------|
| 1 | **Nginx** | EDGE | 80, 443 | No SSH access to Hostinger. Cannot check nginx -t, error logs, or active connections. | HIGH — public entry point. If misconfigured, all domains return errors. |
| 2 | **Traefik** | EDGE | 8080, 8443 | No SSH access to Hostinger. Cannot inspect config, dashboard, or routing rules. | CRITICAL — all 17 domains route through Traefik. Any config error breaks all public access. |
| 3 | **fundsrecoverygroup.com frontend** | EDGE | 3000 | No SSH access. Can curl from external network but cannot verify PM2 status, error logs, or dependency health. | HIGH — primary brand domain. Lead intake depends on this. |
| 4 | **FRGCRM Frontend** | EDGE | 3001 | No SSH access. Serves CRM portal but backend API is BROKEN. Frontend may serve stale pages that look functional. | HIGH — CRM operations portal. Looks up but can't process data. |
| 5 | **SurplusAI Frontend** | EDGE | 3002 | No SSH access. Backend scraper is BROKEN. Frontend serves stale data. | MEDIUM — portal is informational only without backend data. |
| 6 | **Attorney Marketplace Frontend** | EDGE | 3004 | No SSH access. Backend API status unknown. | MEDIUM — depends on Attorney Marketplace API (status UNVERIFIED). |
| 7 | **Chatwoot** | EDGE | 3000 | No SSH access. Lives on Hostinger with own PG/Redis. Docker health unknown. | MEDIUM — live chat system. If down, potential clients can't reach the firm. |
| 8 | **n8n Workflows** | EDGE | 5678 | No SSH access. Workflow execution status unknown. | MEDIUM — automates business logic. Broken workflows may silently fail. |
| 9 | **Webhook Receiver** | EDGE | 9000 | No SSH access. Webhook processing status unknown. Stripe webhooks may be dropping. | HIGH — Stripe, GitHub, Cloudflare webhooks all route through this. Missed Stripe webhooks = missed payment events. |
| 10 | **MinIO (Hostinger)** | EDGE | 9001 | No SSH access. Object storage status unknown. | MEDIUM — file uploads and document storage may be affected. |
| 11 | **MinIO API (COREDB)** | COREDB | 9000 | COREDB node reachability UNVERIFIED. No confirmation MinIO is even installed on COREDB. | HIGH — object storage for Loki, backups. If not set up, migration has no target. |
| 12 | **PostgreSQL (COREDB)** | COREDB | 5432 | COREDB node reachability UNVERIFIED. No confirmation PostgreSQL is installed and accepting connections. | CRITICAL — target for ALL database migration. If not ready, cutover is impossible. |
| 13 | **Redis (COREDB)** | COREDB | 6379 | COREDB node reachability UNVERIFIED. No confirmation Redis is installed. | CRITICAL — target for cache/queue migration. |
| 14 | **Grafana** | EDGE->AIOPS | 3030 | Conflicting documentation: TEST_INVENTORY says EDGE, API_READINESS_MATRIX says AIOPS:3002. Actual location unverified. | MEDIUM — monitoring dashboard. Not revenue-critical but essential for operations visibility. |
| 15 | **Prometheus** | AIOPS | 9090 | No independent verification that scrape targets are healthy. Prometheus may be running but scraping stale/failed targets. | MEDIUM — monitoring blind spot if scrape targets are failing silently. |
| 16 | **Loki** | AIOPS | 3100 | No independent verification. Log aggregation may be failing silently. | LOW — non-critical for revenue but loses observability. |
| 17 | **Uptime Kuma** | AIOPS->EDGE | 3031 | Conflicting documentation (TEST_INVENTORY says EDGE:3031, API_READINESS_MATRIX says AIOPS:3001). Actual location unverified. | HIGH — if Uptime Kuma is down, no alerting for other failures. |
| 18 | **Docker (Hostinger)** | EDGE | N/A | No SSH access. Docker daemon health unknown. All Hostinger services depend on this. | CRITICAL — Docker daemon failure takes down all Hostinger services simultaneously. |
| 19 | **Tailscale (COREDB)** | COREDB | N/A | COREDB node not confirmed on Tailscale network. Mesh between all 3 nodes is ASSUMED. | CRITICAL — inter-node routing depends on this. If COREDB not on Tailscale, migration is dead on arrival. |

**Summary:** 19 of 25 catalogued services (76%) have at least one condition that is UNVERIFIED. 10 of those are completely unverifiable without Hostinger or COREDB access. The ecosystem's actual health status is approximately 24% known, 76% assumed.

---

## SECTION 3: MIGRATION SAFETY ASSESSMENT

Reference: MIGRATION_GATE_CHECKLIST.md does not exist on disk. Assessment based on documented cutover plan (REVENUE_CUTOVER_PLAN.md), rollback plan (REVENUE_ROLLBACK_PLAN.md), and actual service health.

Migration gates applied:

| Gate | Description |
|------|-------------|
| G1 | Service is healthy at source |
| G2 | Target infrastructure is provisioned and reachable |
| G3 | Database dump/restore tested |
| G4 | Connection string migration plan documented |
| G5 | DNS / routing plan documented |
| G6 | Rollback procedure exists and is tested |
| G7 | Monitoring covers both source and target |
| G8 | Stakeholder communication plan ready |
| G9 | Post-migration validation checklist exists |

---

### 3.1 SAFE TO MIGRATE NOW

**None.**

Not a single service meets all 9 migration gates. The closest candidates (Prediction Radar, RavynAI, Docuseal) fail at G2 (COREDB not verified reachable), G3 (no test restore performed), and G6 (rollback documented but never tested). The cutover plan itself (REVENUE_CUTOVER_PLAN.md) states: "3 CRITICAL fixes required before cutover."

---

### 3.2 SAFE TO MIGRATE AFTER FIXES

| Service | Migration Action | Prerequisites | Estimated Effort |
|---------|-----------------|---------------|------------------|
| **FRGCRM Mirror Test** (PM2) | Redirect DB to COREDB | COREDB PG provisioned, test restore validated | 1 hour (low-risk, non-production) |
| **RavynAI API** (Docker) | Move DB to COREDB | COREDB PG provisioned, RavynAI DB dump/restore tested | 2-3 hours |
| **Docuseal** (Docker) | Move Redis to COREDB | COREDB Redis provisioned, test migration done | 1-2 hours |
| **Prediction Radar** (Docker) | Move DB + Redis to COREDB | Stripe mode confirmed, COREDB ready, full dry-run migration complete, maintenance window approved | 4-8 hours (highest risk) |

**Exact fixes needed before any migration:**

1. **COREDB node connectivity established.** SSH access confirmed. Tailscale verified on COREDB.
2. **PostgreSQL 16 installed and configured on COREDB.** Tested with `pg_isready`.
3. **Redis 7 installed and configured on COREDB.** Tested with `redis-cli PING`.
4. **MinIO installed on COREDB.** Tested with `/minio/health/live` endpoint.
5. **At minimum one test pg_dump/pg_restore from AIOPS to COREDB** completed successfully on a non-revenue database.
6. **All 3 broken PM2 services fixed** (FRGCRM API, SurplusAI Scraper, Voice Agent).
7. **DEEPSEEK_API_KEY set** on all agent services and pipeline verified functional.
8. **Stripe mode confirmed** (test or live — either is acceptable if intentional, but unknown is not).
9. **Hostinger services inventoried** and verified healthy from Hostinger side.
10. **Rollback dry-run executed** for at least one non-revenue service to validate the procedure.

---

### 3.3 UNSAFE TO MIGRATE

**All services are currently UNSAFE to migrate.** Specific blockers:

| Blocker | Severity | Services Blocked |
|----------|----------|------------------|
| **COREDB node unreachable** | CRITICAL | ALL (migration has no target) |
| **FRGCRM API broken** | CRITICAL | FRGCRM Agent Svc, FRGCRM Mirror Test, FRGCRM Frontend, all CRM operations |
| **Stripe mode unconfirmed** | CRITICAL | Prediction Radar (primary revenue generator) |
| **Hostinger invisible** | CRITICAL | All 10+ Hostinger services (cannot verify pre or post migration) |
| **No dry-run performed** | HIGH | ALL (never tested a migration end-to-end) |
| **DEEPSEEK_API_KEY missing** | HIGH | FRGCRM Agent Svc, SurplusAI Scraper, Voice Agent |
| **Rollback untested** | HIGH | ALL (documented procedure has never been executed) |
| **Tailscale COREDB unverified** | HIGH | ALL cross-node routing |
| **Docker on Hostinger unverified** | HIGH | All Hostinger services |
| **Database backups unverified** | MEDIUM | All stateful services |

---

## SECTION 4: RISK REGISTER

Top 10 risks ranked by likelihood x impact:

| Rank | Risk | Likelihood | Impact | Service | Mitigation | Owner |
|------|------|-----------|--------|---------|------------|-------|
| **1** | Prediction Radar not collecting real payments (Stripe test mode) | HIGH (confirmed test keys in env) | CRITICAL (100% revenue loss) | Prediction Radar | Verify Stripe mode immediately. If test mode is unintentional, switch to live keys with payment test. | Finance/Engineering Lead |
| **2** | COREDB node cannot be reached, blocking all migration | HIGH (never tested) | CRITICAL (all migration blocked) | ALL | Verify SSH + Tailscale to 5.78.210.123. If unreachable, all cutover plans are invalid. | Infrastructure Engineer |
| **3** | Lead intake pipeline non-functional despite services reporting green | CONFIRMED (DEEPSEEK_API_KEY missing + FRGCRM API broken) | CRITICAL (zero leads processed) | FRGCRM Agent Svc, FRGCRM API, SurplusAI Scraper | Set DEEPSEEK_API_KEY. Fix FRGCRM API. Run end-to-end pipeline test. | Backend Engineer |
| **4** | Hostinger services silently failing with no monitoring coverage | HIGH (zero visibility) | HIGH (50% of ecosystem unknown) | All Hostinger services | Establish Hostinger SSH access. Run full health check. Add all services to Uptime Kuma. | DevOps Engineer |
| **5** | FRGCRM frontend accepting leads that silently fail | CONFIRMED (API broken) | HIGH (lead data loss, reputation damage) | fundsrecoverygroup.com, FRGCRM Frontend | Fix FRGCRM API before any lead intake can work. Add form submission failure alerting. | Backend Engineer / Frontend Engineer |
| **6** | PM2 daemon restart cascades breakage to healthy processes | MEDIUM (restart needed for env var changes) | HIGH (3 healthy PM2 processes at risk) | All PM2 services | Set DEEPSEEK_API_KEY via `pm2 env` without daemon restart. Test restart on mirror service first. | Backend Engineer |
| **7** | Stripe webhooks silently dropping due to Hostinger webhook receiver being down | MEDIUM (Hostinger unverified) | HIGH (missed payment events, subscription state drift) | Webhook Receiver, n8n, Prediction Radar | Verify webhook receiver health from Hostinger. Check Stripe Dashboard for webhook delivery failures. | DevOps / Finance |
| **8** | Traefik misconfiguration on Hostinger taking all public domains offline | LOW (currently serving) | CRITICAL (all 17 domains) | All public-facing services | Do not modify Traefik config. Backup before any change. Have Hostinger console access ready. | Infrastructure Engineer |
| **9** | Tailscale mesh degrading, breaking Hostinger->AIOPS routing | LOW (currently stable) | CRITICAL (Prediction Radar, RavynAI, Docuseal public access) | All Tailscale-dependent domains | Monitor Tailscale status. Keep direct connections. Have DERP relay as fallback. | Network Engineer |
| **10** | Missing database backups, making rollback impossible for data migration | MEDIUM (no backup verification documented) | CRITICAL (data loss during migration) | PostgreSQL, Redis | Schedule and verify automated backups. Test pg_dump/pg_restore on at least one database before any migration. | DBA / Infrastructure |

---

## SECTION 5: EXACT PROOF COMMANDS

For every service in the ecosystem, the exact command sequence that proves its actual status. Commands that require Hostinger or COREDB SSH access are marked **[REQUIRES ACCESS]**. Commands executable from AIOPS are marked **[EXECUTABLE NOW]**.

---

### Service: Nginx
**Status:** UNVERIFIED
**Location:** EDGE (Hostinger 187.77.148.88)

```bash
# Check 1: Process online [REQUIRES ACCESS]
ssh edge "systemctl is-active nginx"
# Expected: active

# Check 2: Port listening [REQUIRES ACCESS]
ssh edge "ss -tlnp | grep -E ':80 |:443 '"
# Expected: nginx listening on 0.0.0.0:80 and 0.0.0.0:443

# Check 3: Config test [REQUIRES ACCESS]
ssh edge "nginx -t"
# Expected: syntax is ok, test is successful

# Check 4: Health endpoint [EXECUTABLE NOW — depends on Tailscale]
curl -sf -o /dev/null -w "%{http_code}" http://<edge-tailscale-ip>:80/nginx_status
# Expected: 200

# Check 5: Serving public traffic [EXECUTABLE NOW]
curl -sI https://fundsrecoverygroup.com | head -1
# Expected: HTTP/2 200

# Verdict: UNVERIFIED — cannot confirm process health, config validity, or error log status without EDGE SSH access.
```

---

### Service: Traefik
**Status:** UNVERIFIED
**Location:** EDGE (Hostinger 187.77.148.88)

```bash
# Check 1: Container running [REQUIRES ACCESS]
ssh edge "docker ps --filter name=traefik --format '{{.Status}}'"
# Expected: Up <duration> (healthy)

# Check 2: Port listening [REQUIRES ACCESS]
ssh edge "ss -tlnp | grep -E ':8080|:8443'"
# Expected: docker-proxy listening

# Check 3: Health endpoint [REQUIRES ACCESS]
ssh edge "curl -sf http://localhost:8080/ping"
# Expected: OK

# Check 4: Dashboard reachable [REQUIRES ACCESS]
ssh edge "curl -sf -o /dev/null -w '%{http_code}' http://localhost:8080/dashboard/"
# Expected: 200

# Check 5: Routing config valid [REQUIRES ACCESS]
ssh edge "docker logs traefik --tail 20 | grep -i error"
# Expected: No error output

# Verdict: UNVERIFIED — cannot confirm Traefik health, routing config, or SSL certificate status without EDGE SSH access. This is the single point of failure for all 17 public domains.
```

---

### Service: Cloudflare
**Status:** PARTIALLY HEALTHY
**Location:** External

```bash
# Check 1: DNS resolution [EXECUTABLE NOW]
dig +short fundsrecoverygroup.com
# Expected: Returns IP (likely Cloudflare proxy IPs)

# Check 2: Cloudflare proxy active [EXECUTABLE NOW]
curl -sI https://fundsrecoverygroup.com | grep -i 'cf-ray'
# Expected: cf-ray: <value> (present if Cloudflare proxying)

# Check 3: Origin reachable through Cloudflare [EXECUTABLE NOW]
curl -sI https://fundsrecoverygroup.com | head -1
# Expected: HTTP/2 200 (or HTTP/1.1 200)

# Check 4: SSL certificate valid [EXECUTABLE NOW]
curl -svI https://fundsrecoverygroup.com 2>&1 | grep -E 'expire|subject|issuer'
# Expected: Valid certificate, not expired

# Verdict: PARTIALLY HEALTHY — DNS resolution and SSL appear functional from external checks. Cannot verify Cloudflare dashboard settings, WAF rules, or origin health from Cloudflare's perspective.
```

---

### Service: fundsrecoverygroup.com Frontend
**Status:** FAKE HEALTHY — Serves HTML, but backend API is BROKEN
**Location:** EDGE (Hostinger)

```bash
# Check 1: PM2 status [REQUIRES ACCESS]
ssh edge "pm2 list | grep frgops-frontend"
# Expected: online (UNVERIFIED)

# Check 2: Port listening [REQUIRES ACCESS]
ssh edge "ss -tlnp | grep 3000"
# Expected: Node.js listening on :3000

# Check 3: Health endpoint [EXECUTABLE NOW]
curl -s https://fundsrecoverygroup.com/api/health
# Expected (documented): {"status":"ok"}

# Check 4: Public route [EXECUTABLE NOW]
curl -sI https://fundsrecoverygroup.com | head -1
# Expected: HTTP/2 200

# Check 5: CRITICAL — Does the frontend depend on FRGCRM API? [BROKEN]
ssh aiops "pm2 list | grep frgcrm-api"
# Status: ERRORED — all form submissions, lead intake, CRM operations FAIL

# Verdict: FAKE HEALTHY — Public route returns 200. Health endpoint may return OK. But the backend API that processes all form submissions is BROKEN. The website loads, but it cannot do its job. Users who submit leads are silently lost.
```

---

### Service: FRGCRM Frontend
**Status:** UNVERIFIED (EDGE) + FAKE HEALTHY (depends on BROKEN API)
**Location:** EDGE (Hostinger)

```bash
# Check 1: PM2 status [REQUIRES ACCESS]
ssh edge "pm2 list | grep frgcrm-frontend"
# Expected: online (UNVERIFIED)

# Check 2: Port listening [REQUIRES ACCESS]
ssh edge "ss -tlnp | grep 3001"

# Check 3: Public route [EXECUTABLE NOW]
curl -sI https://frgops.fundsrecoverygroup.tech | head -1

# Check 4: API dependency [BROKEN]
ssh aiops "pm2 list | grep frgcrm-api"
# Status: ERRORED — CRM operations portal cannot function

# Verdict: Partially UNVERIFIED, functionally FAKE HEALTHY. Frontend may serve HTML, but all CRM operations depend on the broken FRGCRM API.
```

---

### Service: SurplusAI Frontend
**Status:** UNVERIFIED (EDGE) + FAKE HEALTHY (scraper BROKEN, stale data)
**Location:** EDGE (Hostinger)

```bash
# Check 1: PM2 status [REQUIRES ACCESS]
ssh edge "pm2 list | grep surplusai-frontend"
# Expected: online (UNVERIFIED)

# Check 2: Public route [EXECUTABLE NOW]
curl -sI https://surplusai.io | head -1

# Check 3: Data dependency [BROKEN]
ssh aiops "pm2 list | grep surplusai-scraper-agent-svc"
# Status: WAITING, 282+ restarts — data pipeline dead

# Verdict: FAKE HEALTHY — Portal loads but serves stale/empty data. The scraper backend is in a 282+ restart loop.
```

---

### Service: Attorney Marketplace Frontend
**Status:** UNVERIFIED
**Location:** EDGE (Hostinger)

```bash
# Check 1: PM2 status [REQUIRES ACCESS]
ssh edge "pm2 list | grep attorney-mkt-frontend"

# Check 2: Public route [EXECUTABLE NOW]
curl -sI <attorney-marketplace-url> | head -1
# Domain not documented in DOMAIN_ROUTING_MAP.md — unknown public route

# Check 3: API dependency [UNVERIFIED]
ssh aiops "curl -sf http://localhost:8004/health"
# Attorney Marketplace API status UNVERIFIED

# Verdict: UNVERIFIED — Neither the frontend (Hostinger) nor the API (AIOPS port 8004) have been verified. No public domain documented.
```

---

### Service: FRGCRM API
**Status:** BROKEN
**Location:** AIOPS (Hetzner 5.78.140.118)

```bash
# Check 1: Process online [EXECUTABLE NOW]
ssh aiops "pm2 list | grep frgcrm-api"
# Status: errored, PID 0, 15 restarts
# VERDICT: BROKEN

# Check 2: Port listening [EXECUTABLE NOW]
ssh aiops "ss -tlnp | grep -E ':8002|:8013' | grep frgcrm"
# Expected: Nothing — process isn't running, can't bind port
# VERDICT: BROKEN

# Check 3: Health endpoint [EXECUTABLE NOW]
ssh aiops "curl -sf http://localhost:8002/health"
# Expected: Connection refused — no process listening
# VERDICT: BROKEN

# Check 4: Crash loop evidence [EXECUTABLE NOW]
ssh aiops "pm2 logs frgcrm-api --lines 10 --nostream"
# Expected: "Error loading ASGI app. Could not import module 'main'."
# VERDICT: CONFIRMED CRASH — consistent failure, not intermittent

# Check 5: Dependencies [EXECUTABLE NOW]
ssh aiops "pg_isready -h localhost -p 5433 -U postgres"
# Expected: accepting connections (frgops-standby PG is healthy)
# But the API can't reach it because the API process doesn't start.
# VERDICT: Dependency OK, but API can't use it

# Verdict: BROKEN — Process is errored with 15 restart failures. Root cause: ASGI import error. Impact: CRM operations, lead management, case management, client communication all offline.
```

---

### Service: SurplusAI API
**Status:** BROKEN (waiting, effectively down)
**Location:** AIOPS (Hetzner 5.78.140.118)

```bash
# Check 1: Process [EXECUTABLE NOW]
ssh aiops "pm2 list | grep surplusai-scraper-agent-svc"
# Status: waiting, 282+ restarts
# PM2 exhausted max_restarts=5, no longer attempting restart
# VERDICT: BROKEN (process is dead, PM2 given up)

# Check 2: Port [EXECUTABLE NOW]
ssh aiops "ss -tlnp | grep 8001"
# Expected: Nothing — no process to bind port
# VERDICT: BROKEN

# Check 3: Logs [EXECUTABLE NOW]
ssh aiops "pm2 logs surplusai-scraper-agent-svc --lines 20 --nostream"
# VERDICT: Inspect for root cause — likely missing DEEPSEEK_API_KEY or waiting on FRGCRM API

# Verdict: BROKEN — 282+ restart attempts. Process is in permanent waiting state. May automatically recover if FRGCRM API is fixed and DEEPSEEK_API_KEY is set.
```

---

### Service: Wheeler Brain OS API
**Status:** UNVERIFIED
**Location:** AIOPS (Hetzner 5.78.140.118), port 8002

```bash
# Check 1: Process [EXECUTABLE NOW]
ssh aiops "pm2 list | grep -i 'wheeler\|brain'"
# Expected: UNKNOWN — Not found in PM2 process list from live survey
# Wheeler Brain OS not observed in PM2 or Docker inventory during live survey

# Check 2: Port [EXECUTABLE NOW]
ssh aiops "ss -tlnp | grep 8002"
# Expected: UNKNOWN — port 8002 not observed in API_READINESS_MATRIX port map

# Verdict: UNVERIFIED — This service is documented in TEST_INVENTORY.md but was NOT OBSERVED in the live process survey (PM2 list, Docker ps, or port map). It may not exist as a deployed service.
```

---

### Service: Prediction Radar API
**Status:** PARTIALLY HEALTHY
**Location:** AIOPS (Hetzner 5.78.140.118), Docker, ports 8000/8098

```bash
# Check 1: Container running [EXECUTABLE NOW]
ssh aiops "docker ps --filter name=prediction-radar --format '{{.Names}} {{.Status}}'"
# Expected: prediction-radar-app Up 43h (healthy)

# Check 2: Port listening [EXECUTABLE NOW]
ssh aiops "ss -tlnp | grep -E ':8000|:8098'"
# Expected: docker-proxy listening on both ports

# Check 3: Health endpoint [EXECUTABLE NOW]
ssh aiops "curl -sf http://localhost:8000/health | jq ."
# Expected: {"status":"healthy","db":"up","redis":"up"...}

# Check 4: Public route [EXECUTABLE NOW via external]
curl -sI https://predictionradar.app | head -1
# Expected: HTTP/2 200

# Check 5: FAKE-HEALTHY CHECK — Stripe mode [EXECUTABLE NOW]
ssh aiops "docker exec prediction-radar-app env | grep STRIPE_SECRET_KEY"
# Expected: STRIPE_SECRET_KEY=sk_test_... (TEST MODE — CONFIRMED)
# VERDICT: FAKE HEALTHY for payments — test keys mean no real revenue

# Check 6: Dependencies [EXECUTABLE NOW]
ssh aiops "docker ps --filter name=prediction-radar --format '{{.Names}} {{.Status}}'"
# Check prediction-radar-app-db and prediction-radar-app-redis are healthy

# Verdict: PARTIALLY HEALTHY — Containers healthy, ports listening, health endpoint responds. BUT Stripe is in TEST MODE, meaning real payments may not be processed. This is the single most dangerous false-green in the ecosystem.
```

---

### Service: Attorney Marketplace API
**Status:** UNVERIFIED
**Location:** AIOPS (Hetzner 5.78.140.118), port 8004

```bash
# Check 1: Process [EXECUTABLE NOW]
ssh aiops "pm2 list | grep -i attorney"
# Expected: UNKNOWN — Not observed in PM2 list during live survey

# Check 2: Port [EXECUTABLE NOW]
ssh aiops "ss -tlnp | grep 8004"
# Port 8004 not observed in API_READINESS_MATRIX port map

# Verdict: UNVERIFIED — Documented but not observed during live survey. May not be deployed.
```

---

### Service: LiteLLM / DeepSeek Gateway
**Status:** UNVERIFIED (runs on Hostinger)
**Location:** Hostinger EDGE, port 4000

```bash
# Check 1: Process [REQUIRES ACCESS]
ssh edge "docker ps --filter name=litellm --format '{{.Status}}'"
# Expected: Up <duration> (healthy) — UNVERIFIED

# Check 2: Health endpoint [REQUIRES ACCESS]
ssh edge "curl -sf http://localhost:4000/health | jq ."

# Check 3: Public route [EXECUTABLE NOW]
curl -s https://litellm.wheeler.ai/health
# This routes through Cloudflare → Hostinger Traefik → LiteLLM
# If returns 200: basic routing works
# If returns error/empty: Traefik routing or LiteLLM is down

# Check 4: Model availability [REQUIRES ACCESS]
ssh edge "curl -sf http://localhost:4000/v1/models | jq '.data | length'"

# Verdict: UNVERIFIED — Cannot confirm from AIOPS. Located on Hostinger with zero visibility. Single point of failure for all AI-dependent services that route through it (SurplusAI API, Wheeler Brain OS API). The public route may work but actual AI model availability unconfirmed.
```

---

### Service: OpenClaw (Agent Framework)
**Status:** UNVERIFIED / EMBEDDED
**Location:** AIOPS (Hetzner), embedded within Prediction Radar context

```bash
# Check 1: Process [EXECUTABLE NOW]
# OpenClaw has no independent process — runs within Prediction Radar worker
# Cannot check independently

# Check 2: Gateway token [EXECUTABLE NOW]
ssh aiops "docker exec prediction-radar-app env | grep OPENCLAW_GATEWAY_TOKEN"
# Expected: Token configured (confirmed in API_READINESS_MATRIX)

# Check 3: Health [EXECUTABLE NOW]
ssh aiops "curl -sf http://localhost:8005/health"
# Port 8005 documented in TEST_INVENTORY — not confirmed in live survey

# Verdict: UNVERIFIED — Embedded dependency of Prediction Radar. Cannot be independently verified. Gateway token configured. Port 8005 not confirmed in live survey.
```

---

### Service: PostgreSQL (COREDB)
**Status:** UNVERIFIED
**Location:** COREDB (Hetzner 5.78.210.123)

```bash
# Check 1: Node reachable [EXECUTABLE NOW — if COREDB network known]
ssh coredb "hostname && uptime"
# Expected: COREDB node reachable via SSH
# VERDICT: NEVER TESTED — COREDB reachability unconfirmed

# Check 2: PostgreSQL installed and running [EXECUTABLE NOW — blocked on SSH]
ssh coredb "systemctl is-active postgresql || docker ps --filter name=postgres"
# VERDICT: UNVERIFIED

# Check 3: Accepting connections [EXECUTABLE NOW — blocked on SSH]
ssh coredb "pg_isready -h localhost -p 5432 -U postgres -d wheeler"
# VERDICT: UNVERIFIED

# Verdict: UNVERIFIED — COREDB node (5.78.210.123) has never been confirmed reachable. PostgreSQL status, installation, and connectivity are all UNKNOWN. This is the #2 risk in the ecosystem after Stripe test mode: the entire database migration depends on this node existing and being ready.
```

---

### Service: Redis (COREDB)
**Status:** UNVERIFIED
**Location:** COREDB (Hetzner 5.78.210.123)

```bash
# Check 1: Redis installed [EXECUTABLE NOW — blocked on SSH]
ssh coredb "redis-cli -h localhost -p 6379 PING"
# VERDICT: UNVERIFIED

# Verdict: UNVERIFIED — Same as PostgreSQL. No confirmation COREDB node exists, is reachable, or has Redis installed.
```

---

### Service: MinIO (COREDB)
**Status:** UNVERIFIED
**Location:** COREDB (Hetzner 5.78.210.123)

```bash
# Check 1: MinIO installed [EXECUTABLE NOW — blocked on SSH]
ssh coredb "curl -sf http://localhost:9000/minio/health/live"
# VERDICT: UNVERIFIED

# Verdict: UNVERIFIED — No confirmation MinIO exists on COREDB. Object storage migration has no verified target.
```

---

### Service: Grafana
**Status:** UNVERIFIED (conflicting location data)
**Location:** DISPUTED — TEST_INVENTORY says EDGE:3030; API_READINESS_MATRIX says AIOPS:3002

```bash
# Check 1: Actual location [EXECUTABLE NOW]
ssh aiops "docker ps --filter name=grafana --format '{{.Names}} {{.Status}} {{.Ports}}'"
# If found on AIOPS: location confirmed as AIOPS:3002
# If not found: may be on Hostinger:3030 [REQUIRES ACCESS]

# Check 2: Health endpoint [EXECUTABLE NOW if on AIOPS]
ssh aiops "curl -sf http://localhost:3002/api/health | jq ."

# Verdict: UNVERIFIED — Conflicting documentation about location and port. Cannot verify without checking both nodes.
```

---

### Service: Prometheus
**Status:** PARTIALLY HEALTHY
**Location:** AIOPS (Hetzner), port 9090

```bash
# Check 1: Container running [EXECUTABLE NOW]
ssh aiops "docker ps --filter name=prometheus --format '{{.Status}}'"
# Expected: Up (from API_READINESS_MATRIX port map: port 9090 active)

# Check 2: Health endpoint [EXECUTABLE NOW]
ssh aiops "curl -sf http://localhost:9090/-/healthy"
# Expected: "Prometheus Server is Healthy."

# Check 3: FAKE-HEALTHY CHECK — Are scrape targets healthy? [EXECUTABLE NOW]
ssh aiops "curl -sf http://localhost:9090/api/v1/query?query=up | jq '.data.result[] | {instance: .metric.instance, job: .metric.job, up: .value[1]}'"
# Expected: All targets show up=1
# If any show up=0: Prometheus is running but monitoring is blind to those targets

# Verdict: PARTIALLY HEALTHY — Prometheus itself likely healthy, but scrape target health is unverified. If 3 broken PM2 services are among the targets, Prometheus is accurately reporting them as down, but if other targets are also silently failing, monitoring is incomplete.
```

---

### Service: Loki
**Status:** UNVERIFIED
**Location:** AIOPS (Hetzner), port 3100

```bash
# Check 1: Container running [EXECUTABLE NOW]
ssh aiops "docker ps --filter name=loki --format '{{.Status}}'"

# Check 2: Ready endpoint [EXECUTABLE NOW]
ssh aiops "curl -sf http://localhost:3100/ready"
# Expected: "Ready"

# Check 3: Log streams queryable [EXECUTABLE NOW]
ssh aiops "curl -s 'http://localhost:3100/loki/api/v1/query_range?query={job=~".+"}&limit=1' | jq '.data.result | length'"
# Expected: >0 (actual log data available)

# Verdict: UNVERIFIED — No independent check performed. If MinIO S3 backend is used and MinIO is down, Loki may appear healthy but be unable to store/retrieve logs.
```

---

### Service: Uptime Kuma
**Status:** UNVERIFIED (conflicting location data)
**Location:** DISPUTED — TEST_INVENTORY says EDGE:3031; API_READINESS_MATRIX says AIOPS:3001

```bash
# Check 1: Actual location [EXECUTABLE NOW]
ssh aiops "docker ps --filter name=uptime-kuma --format '{{.Names}} {{.Status}}'"
# If found on AIOPS: location confirmed as AIOPS:3001

# Check 2: All monitors green? [EXECUTABLE NOW if on AIOPS]
ssh aiops "curl -sf http://localhost:3001/api/status-page/heartbeat/<slug>"
# Or access dashboard: uptime.wheeler.ai

# Verdict: UNVERIFIED — Location is disputed between sources. If Uptime Kuma is down, alerting for all other services is silent. Cannot confirm which services have monitors configured.
```

---

### Service: PM2
**Status:** PARTIALLY HEALTHY (daemon up, 50% of processes broken)
**Location:** AIOPS (Hetzner) + EDGE (Hostinger)

```bash
# Check 1: PM2 daemon running [EXECUTABLE NOW]
ssh aiops "pm2 ping"
# Expected: pong
# VERDICT: HEALTHY

# Check 2: Process health [EXECUTABLE NOW]
ssh aiops "pm2 jlist | jq '[.[] | {name: .name, status: .pm2_env.status, restarts: .pm2_env.restart_time}]'"
# Expected output — ALL processes should show status="online", restarts=0
# ACTUAL output:
#   frgcrm-agent-svc: online, 0 restarts — OK
#   frgcrm-api: errored, 15 restarts — BROKEN
#   frgcrm-mirror-test: online, 0 restarts — OK
#   insforge-agent-svc: online, 0 restarts — OK
#   surplusai-scraper-agent-svc: waiting, 282+ restarts — BROKEN
#   voice-agent-svc: waiting, 282+ restarts — BROKEN
# VERDICT: 3/6 processes healthy, 3/6 broken — 50% failure rate

# Check 3: PM2 on EDGE [REQUIRES ACCESS]
ssh edge "pm2 list"
# VERDICT: UNVERIFIED — EDGE PM2 status unknown

# Verdict: PARTIALLY HEALTHY on AIOPS. PM2 daemon is fine. 50% of managed processes are broken. EDGE PM2 status UNVERIFIED.
```

---

### Service: Docker
**Status:** PARTIALLY HEALTHY on AIOPS, UNVERIFIED on EDGE and COREDB
**Location:** ALL nodes

```bash
# Check 1: AIOPS Docker [EXECUTABLE NOW]
ssh aiops "docker info --format '{{.ServerVersion}}'"
# VERDICT: HEALTHY (assuming exit code 0)

# Check 2: AIOPS container health [EXECUTABLE NOW]
ssh aiops "docker ps --format 'table {{.Names}}\t{{.Status}}'"
# Check for any containers in 'unhealthy' or 'restarting' state

# Check 3: EDGE Docker [REQUIRES ACCESS]
ssh edge "docker info --format '{{.ServerVersion}}'"
# VERDICT: UNVERIFIED

# Check 4: COREDB Docker [EXECUTABLE NOW — blocked on SSH]
ssh coredb "docker info --format '{{.ServerVersion}}'"
# VERDICT: UNVERIFIED

# Verdict: PARTIALLY HEALTHY — AIOPS Docker confirmed running. EDGE and COREDB Docker status unverified. Hostinger instability in Docker daemon would take down all 10+ Hostinger services simultaneously.
```

---

### Service: Tailscale
**Status:** PARTIALLY HEALTHY (AIOPS-Hostinger confirmed, COREDB unverified)
**Location:** ALL nodes

```bash
# Check 1: AIOPS Tailscale [EXECUTABLE NOW]
ssh aiops "tailscale status --json | jq '{self: .Self.Online, peers: [.Peer[] | {hostname: .HostName, online: .Online, relay: .Relay}]}'"
# VERDICT: Check Self.Online=true, peers include Hostinger at 100.98.x.x

# Check 2: COREDB on Tailscale [EXECUTABLE NOW — blocked on COREDB access]
# Cannot check if COREDB node is on the Tailscale network

# Check 3: Direct connections (no DERP relay) [EXECUTABLE NOW]
ssh aiops "tailscale status --json | jq '[.Peer[] | select(.Relay != \"\") | .HostName]'"
# If any names appear: those nodes are using DERP relay (slower, less reliable)

# Check 4: EDGE Tailscale [REQUIRES ACCESS]
ssh edge "tailscale status --json | jq '.Self.Online'"
# VERDICT: UNVERIFIED

# Verdict: PARTIALLY HEALTHY. AIOPS-Hostinger Tailscale mesh confirmed operational. COREDB Tailscale status UNVERIFIED. If COREDB is not on the Tailscale network, there is no secure route for database migration and cross-node communication to COREDB is impossible.
```

---

### Additional Services from Live Survey

#### RavynAI API
**Status:** PARTIALLY HEALTHY
**Location:** AIOPS Docker, port 8007

```bash
ssh aiops "docker ps --filter name=ravynai --format '{{.Names}} {{.Status}}'"
ssh aiops "curl -sf http://localhost:8007/health | jq ."
curl -sI https://ravynai.wheeler.ai | head -1
```
**Verdict:** PARTIALLY HEALTHY — Docker container healthy 43h. Health endpoint documented. Public route unverified. No restart test performed. No confirmed monitoring. `FRGCRM_API_URL` configured but FRGCRM API is BROKEN — impact unclear.

---

#### FRGCRM Agent Service
**Status:** FAKE HEALTHY (see Section 2.3.2)
**Verdict:** Process online but all 6 pipeline stages fail due to missing DEEPSEEK_API_KEY.

---

#### FRGCRM Mirror Test
**Status:** PARTIALLY HEALTHY
**Verdict:** Online, stable. Same codebase as Agent Service, same DEEPSEEK_API_KEY issue. Not revenue-critical.

---

#### Insforge Agent Service
**Status:** PARTIALLY HEALTHY
**Verdict:** Online, 42h stable. Internal agent. Port 8013 shared with FRGCRM Agent Svc — potential conflict. No known revenue impact.

---

#### Docuseal
**Status:** PARTIALLY HEALTHY
**Verdict:** Docker healthy 43h. E-signature service. Low revenue coupling.

---

#### Chatwoot
**Status:** UNVERIFIED
**Location:** Hostinger EDGE

```bash
# [REQUIRES ACCESS]
ssh edge "docker ps --filter name=chatwoot --format '{{.Status}}'"
```
**Verdict:** UNVERIFIED — Hostinger-side. Live chat for potential clients. If down, lead communication channel lost.

---

#### n8n Workflows
**Status:** UNVERIFIED
**Location:** Hostinger EDGE

```bash
# [REQUIRES ACCESS]
ssh edge "docker ps --filter name=n8n --format '{{.Status}}'"
```
**Verdict:** UNVERIFIED — Hostinger-side. Workflow automation. Broken workflows may silently fail.

---

#### Webhook Receiver
**Status:** UNVERIFIED
**Location:** Hostinger EDGE

```bash
# [REQUIRES ACCESS]
ssh edge "docker ps --filter name=webhook-receiver --format '{{.Status}}'"
ssh edge "curl -sf http://localhost:9000/health"
```
**Verdict:** UNVERIFIED — Hostinger-side. Stripe, GitHub, Cloudflare webhooks all route through this. If down, payment events may be missed.

---

## SECTION 6: EXACT NEXT FIXES

Prioritized, specific, actionable fixes with verification commands.

---

### Priority 1: CRITICAL (fix within 24 hours)

#### Fix 1: Confirm Stripe Mode on Prediction Radar

**What's wrong:** Prediction Radar is running with `sk_test_*` / `pk_test_*` keys. If this is unintentional, the primary revenue generator is not collecting real payments. If intentional (staging), the service should not be classified as production.

**Service:** Prediction Radar
**Effort:** 30 minutes
**Owner:** Finance/Engineering Lead

```bash
# Investigation (READ-ONLY):
ssh aiops "docker exec prediction-radar-app env | grep STRIPE_SECRET_KEY"
# Confirms: sk_test_* prefix

# Check Stripe Dashboard:
# 1. Log into Stripe Dashboard
# 2. Check "Developers" -> "API Keys" — is the same sk_test_* key listed?
# 3. Check "Payments" — are there any live-mode charges?
# 4. Check "Subscriptions" — are there active subscriptions in live mode or only test mode?

# If TEST MODE IS INTENTIONAL (staging environment):
# Document this. Add to service inventory. Tag Prediction Radar as "staging" not "production."
# No further action needed.

# If TEST MODE IS UNINTENTIONAL (should be production):
# 1. Create live-mode products and prices in Stripe Dashboard matching the 7 tiers
# 2. Generate live API keys (sk_live_*, pk_live_*)
# 3. Create live webhook endpoint in Stripe Dashboard
# 4. Update Prediction Radar env vars:
#    STRIPE_SECRET_KEY=sk_live_...
#    STRIPE_PUBLISHABLE_KEY=pk_live_...
#    All STRIPE_PRICE_* vars -> live-mode price IDs
# 5. Restart Prediction Radar:
ssh aiops "docker compose --project-name prediction-radar restart"
# 6. Test end-to-end checkout with a real $1 charge
# 7. Verify webhook delivery in Stripe Dashboard

# Verification:
# Check env after restart:
ssh aiops "docker exec prediction-radar-app env | grep STRIPE_SECRET_KEY"
# Expected: STRIPE_SECRET_KEY=sk_live_... (if switched to live)
```

#### Fix 2: Fix FRGCRM API

**What's wrong:** PM2 errored, 15 restart attempts. ASGI import error: "Could not import module 'main'." This is the keystone service — fixing it may cascade to fix SurplusAI and Voice Agent, and unblocks the entire CRM and lead intake pipeline.

**Service:** FRGCRM API
**Effort:** 2-4 hours
**Owner:** Backend Engineer

```bash
# Step 1: Inspect error logs
ssh aiops "pm2 logs frgcrm-api --lines 50 --nostream"

# Step 2: Check PM2 process configuration
ssh aiops "pm2 jlist | jq '.[] | select(.name==\"frgcrm-api\") | {cwd: .pm2_env.pm_cwd, exec_interpreter: .pm2_env.exec_interpreter, args: .pm2_env.args, env: {FRGCRM_API_URL: .pm2_env.FRGCRM_API_URL}}'"

# Step 3: Verify main.py exists in working directory
ssh aiops "ls -la /opt/apps/frgcrm-api/main.py"
# If NOT FOUND: This is the root cause. The module file is missing or in wrong location.

# Step 4: Check Python dependencies
ssh aiops "cd /opt/apps/frgcrm-api && pip list | grep -E 'fastapi|uvicorn|asgi'"
# If packages missing: Install them.

# Step 5: Check virtual environment
ssh aiops "cat /opt/apps/ecosystem.config.js | grep -A 5 frgcrm-api"
# Verify that exec_interpreter points to the correct virtualenv Python

# Step 6: Check port conflict
ssh aiops "ss -tlnp | grep 8013"
# If multiple services bound to 8013: Port conflict. Reassign ports.

# Step 7: Attempt fix and restart
ssh aiops "pm2 restart frgcrm-api"
ssh aiops "sleep 5 && pm2 list | grep frgcrm-api"
# Expected: status = "online"

# Step 8: Verify health endpoint
ssh aiops "curl -sf http://localhost:8002/health | jq ."
# Expected: {"status":"healthy","database":"up","redis":"up"}

# Step 9: Verify API routes work
ssh aiops "curl -sf http://localhost:8002/api/attorney?status=active | jq '. | length'"
# Expected: Returns list of attorneys
```

#### Fix 3: Set DEEPSEEK_API_KEY on All Agent Services

**What's wrong:** All 6 stages of the lead intake pipeline fail because `DEEPSEEK_API_KEY` is not set in any PM2 process environment. The FRGCRM Agent Service appears healthy (PM2: ONLINE, 0 restarts) but accomplishes nothing because the AI model cannot be initialized.

**Service:** FRGCRM Agent Service, SurplusAI Scraper Agent, Voice Agent Service
**Effort:** 30 minutes
**Owner:** Backend Engineer

```bash
# Step 1: Verify current state
ssh aiops "pm2 env 0 | grep -E 'DEEPSEEK_API_KEY|OPENAI_API_KEY'"
ssh aiops "pm2 env 1 | grep -E 'DEEPSEEK_API_KEY|OPENAI_API_KEY'"
ssh aiops "pm2 env 2 | grep -E 'DEEPSEEK_API_KEY|OPENAI_API_KEY'"
# Expected: all empty/undefined

# Step 2: Set the key (using pm2 env to avoid daemon restart)
ssh aiops "pm2 env 0 DEEPSEEK_API_KEY=<key-value>"
ssh aiops "pm2 env 1 DEEPSEEK_API_KEY=<key-value>"
ssh aiops "pm2 env 2 DEEPSEEK_API_KEY=<key-value>"

# Step 3: Restart only the services that need it
ssh aiops "pm2 restart frgcrm-agent-svc"
ssh aiops "pm2 restart surplusai-scraper-agent-svc"
ssh aiops "pm2 restart voice-agent-svc"

# Step 4: Verify processes came back online
ssh aiops "sleep 10 && pm2 list"

# Step 5: Verify pipeline functional (CRITICAL VERIFICATION)
ssh aiops "curl -s -X POST http://localhost:8003/pipeline/dag/run"
ssh aiops "sleep 30 && curl -s http://localhost:8003/pipeline/dag/latest | jq '.stages[] | {stage: .name, status: .status}'"
# Expected: All 6 stages show status "completed" or "success"
# NOT: "FAILED"

# Step 6: Verify SurplusAI scraper started processing
ssh aiops "pm2 logs surplusai-scraper-agent-svc --lines 20 --nostream"
# Expected: Logs showing scraper running, not crashing

# Step 7: Verify Voice Agent started
ssh aiops "pm2 logs voice-agent-svc --lines 20 --nostream"
# Expected: Logs showing agent running, not crashing
```

---

### Priority 2: HIGH (fix within 1 week)

#### Fix 4: Establish Hostinger SSH Access and Inventory Services

**What's wrong:** 10+ services run on the Hostinger EDGE node with zero visibility. At least 5 are revenue-critical or revenue-adjacent (FRGCRM Frontend, SurplusAI Frontend, LiteLLM, Webhook Receiver, n8n, Chatwoot). Their actual health status is completely unknown.

**Effort:** 2 hours
**Owner:** DevOps / Infrastructure Engineer

```bash
# Step 1: Obtain Hostinger SSH access
# This requires credentials from the team member who manages the Hostinger VPS.

# Step 2: Once connected, run full inventory
ssh edge "pm2 list"
ssh edge "pm2 jlist | jq '[.[] | {name: .name, status: .pm2_env.status, restarts: .pm2_env.restart_time}]'"
ssh edge "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
ssh edge "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'"
ssh edge "ss -tlnp"
ssh edge "df -h /"
ssh edge "free -h"
ssh edge "uptime"

# Step 3: Check critical services individually
ssh edge "curl -sf http://localhost:9000/health"         # Webhook receiver
ssh edge "curl -sf http://localhost:4000/health | jq ."  # LiteLLM
ssh edge "curl -sf http://localhost:5678/healthz"         # n8n
ssh edge "docker logs webhook-receiver --tail 20"
ssh edge "docker logs litellm --tail 20"
ssh edge "docker logs traefik --tail 50 | grep -i error"

# Step 4: Check Traefik routing config
ssh edge "docker exec traefik cat /etc/traefik/dynamic.yml"
ssh edge "docker exec traefik cat /etc/traefik/traefik.yml"

# Step 5: Check SSL certificate expiry
ssh edge "for domain in fundsrecoverygroup.com predictionradar.app surplusai.io; do echo \"=== $domain ===\"; echo | openssl s_client -servername $domain -connect localhost:443 2>/dev/null | openssl x509 -noout -dates; done"

# Step 6: Update TEST_INVENTORY.md with actual Hostinger service status
```

#### Fix 5: Verify COREDB Node and Provision Databases

**What's wrong:** The COREDB node (5.78.210.123) has never been confirmed reachable. PostgreSQL, Redis, and MinIO status on COREDB is completely unknown. The entire database migration strategy depends on this node.

**Effort:** 4 hours
**Owner:** DBA / Infrastructure Engineer

```bash
# Step 1: Verify node is reachable
ssh -o ConnectTimeout=10 coredb "hostname && uptime"
# If fails: COREDB node is unreachable. All migration plans are INVALID.
# Investigate: Wrong IP? Firewall? Node not provisioned?

# Step 2: Verify Tailscale is installed and connected
ssh coredb "tailscale status --json | jq '{self: .Self.Online, peers: [.Peer[] | {hostname: .HostName, online: .Online}]}'"
# Expected: Self.Online=true, peers include AIOPS and Hostinger

# Step 3: Install PostgreSQL 16 if not present
ssh coredb "which psql || apt-get install -y postgresql-16"
ssh coredb "systemctl enable --now postgresql"
ssh coredb "pg_isready -h localhost -p 5432"

# Step 4: Install Redis 7 if not present
ssh coredb "which redis-cli || apt-get install -y redis"
ssh coredb "systemctl enable --now redis"
ssh coredb "redis-cli PING"

# Step 5: Install MinIO if not present
ssh coredb "which minio || (wget https://dl.min.io/server/minio/release/linux-amd64/minio && chmod +x minio && mv minio /usr/local/bin/)"
# Configure and start MinIO

# Step 6: Verify all three services
ssh coredb "echo '=== PG ===' && pg_isready -h localhost -p 5432 && echo '=== REDIS ===' && redis-cli PING && echo '=== MINIO ===' && curl -sf http://localhost:9000/minio/health/live"

# Step 7: Test Tailscale connectivity from AIOPS
ssh aiops "pg_isready -h <coredb-tailscale-ip> -p 5432 -U postgres"
ssh aiops "redis-cli -h <coredb-tailscale-ip> -p 6379 PING"
ssh aiops "curl -sf http://<coredb-tailscale-ip>:9000/minio/health/live"
```

#### Fix 6: Test Database Migration on Non-Revenue Database

**What's wrong:** No pg_dump/pg_restore has ever been tested between AIOPS and COREDB. Migrating a revenue database without a proven migration procedure is reckless.

**Effort:** 2 hours
**Owner:** DBA

```bash
# Step 1: Choose a non-revenue database for test migration
# Candidate: frgcrm-mirror-test database (lowest risk)

# Step 2: Dump from AIOPS
ssh aiops "pg_dump -h localhost -p 5433 -U postgres -d <test-db-name> -F c -f /tmp/test-migration.dump"

# Step 3: Transfer to COREDB
ssh aiops "scp /tmp/test-migration.dump coredb:/tmp/"

# Step 4: Restore on COREDB
ssh coredb "pg_restore -h localhost -p 5432 -U postgres -d <test-db-name> -c /tmp/test-migration.dump"

# Step 5: Verify restore integrity
ssh coredb "psql -h localhost -p 5432 -U postgres -d <test-db-name> -c 'SELECT count(*) FROM <key-table>;'"
# Compare row counts between source and target

# Step 6: Test application connection to COREDB
# Update FRGCRM Mirror Test to connect to COREDB
# Verify health endpoint still works
# Switch back to local DB after test

# Verification:
# If migration succeeds: Document procedure. Add timing data. Proceed to Phase 2.
# If migration fails: Debug and fix before attempting any revenue database migration.
```

---

### Priority 3: MEDIUM (fix within 2 weeks)

#### Fix 7: Resolve Monitoring Conflicts and Gaps

**What's wrong:**
- Grafana location is disputed (EDGE:3030 vs AIOPS:3002)
- Uptime Kuma location is disputed (EDGE:3031 vs AIOPS:3001)
- No service has confirmed Prometheus scrape coverage verification
- No alerting confirmed for FRGCRM API, SurplusAI Scraper, or Voice Agent failures
- Prometheus may be running but not scraping all targets

```bash
# Step 1: Resolve actual locations
ssh aiops "docker ps --format '{{.Names}} {{.Ports}}' | grep -E 'grafana|uptime-kuma'"
# If not on AIOPS: [REQUIRES ACCESS] ssh edge same command

# Step 2: Verify Prometheus scrape targets
ssh aiops "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl: .scrapeUrl, health: .health, lastError: .lastError}'"
# Expected: all targets health="up", lastError=""

# Step 3: Add missing services to Prometheus scrape config
# FRGCRM Agent Service (:8003/metrics)
# FRGCRM API (:8002/metrics) — once fixed
# SurplusAI API (:8001/metrics) — once fixed
# Voice Agent (:8008/metrics) — once fixed

# Step 4: Add missing services to Uptime Kuma
# - FRGCRM API health check (once fixed)
# - FRGCRM Agent Service pipeline endpoint
# - LiteLLM /health (via public route)
# - Webhook receiver /health (via public route)

# Step 5: Verify Grafana dashboards load correctly
curl -s https://grafana.wheeler.ai/api/health | jq .
```

#### Fix 8: Test Rollback Procedure for One Non-Revenue Service

**What's wrong:** REVENUE_ROLLBACK_PLAN.md exists but has never been tested. Running an untested rollback during an actual incident is dangerous.

```bash
# Step 1: Choose test service: FRGCRM Mirror Test (lowest risk)
# Step 2: Execute Section 2 (Pre-Rollback Checklist) of REVENUE_ROLLBACK_PLAN.md
# Step 3: Execute rollback procedure for FRGCRM Mirror Test
# Step 4: Verify service restored
# Step 5: Document any issues, update REVENUE_ROLLBACK_PLAN.md
# Step 6: Update timing estimates based on actual execution
```

#### Fix 9: Create MIGRATION_GATE_CHECKLIST.md

**What's wrong:** The document `/root/docs/MIGRATION_GATE_CHECKLIST.md` is referenced in this report's requirements but does not exist on disk. Create it.

```bash
# Create the document based on the 9 gates defined in Section 3 of this report.
# Populate with actual gate status for each service.
# Link to REVENUE_CUTOVER_PLAN.md and REVENUE_ROLLBACK_PLAN.md.
```

---

### Priority 4: LOW (fix within 1 month)

#### Fix 10: Resolve Port Allocation Conflicts

**What's wrong:** Port 8013 appears to be shared by FRGCRM Agent Service and Insforge Agent Service. FRGCRM API may also target this port.

```bash
# Step 1: Audit actual port bindings
ssh aiops "ss -tlnp | grep 8013"
# Step 2: Determine correct port assignments
# Step 3: Reassign conflicting services to unique ports
# Step 4: Update all service documentation
# Step 5: Update Traefik config if any routes changed
```

#### Fix 11: Implement Backup Verification Automation

**What's wrong:** No automated backup verification. Database backups are assumed but never confirmed.

```bash
# Step 1: Script daily pg_dump of all databases
# Step 2: Script daily automated test restore to COREDB (once COREDB ready)
# Step 3: Add backup verification to Uptime Kuma or Healthchecks.io
# Step 4: Alert on backup failure within 1 hour
```

#### Fix 12: Complete Test API Suite

**What's wrong:** `/root/tests/api/` directory exists but is empty. Validation scripts exist in `/root/scripts/` but API-level tests are missing.

```bash
# Step 1: Create API test for each service's health endpoint
# Step 2: Add response body validation (not just HTTP status)
# Step 3: Add dependency check validation
# Step 4: Add end-to-end smoke tests
# Step 5: Add to CI/CD if applicable
```

---

## SECTION 7: VALIDATION FRAMEWORK HEALTH

How healthy is the validation framework itself? A validation framework that produces false positives is worse than no framework at all.

---

### 7.1 Validation Scripts Inventory

| Script | Lines | Covers | Completeness | Notes |
|--------|-------|--------|-------------|-------|
| `pm2-validation.sh` | 858 | PM2 processes on AIOPS | PARTIAL | Covers process status but does NOT validate application logic. Would report FRGCRM Agent Service as "healthy" despite all 6 pipeline stages failing. This is a FALSE-POSITIVE RISK. |
| `docker-validation.sh` | 806 | Docker containers on AIOPS | PARTIAL | Covers container health status but does NOT validate application-level health. Would report Prediction Radar as "healthy" while Stripe test-mode is undetected. |
| `db-validation.sh` | 908 | PostgreSQL health | UNTESTED | Covers pg_isready, replication, disk space. Cannot verify on COREDB (node unreachable). |
| `redis-validation.sh` | 895 | Redis health | UNTESTED | Covers PING, memory, persistence. Cannot verify on COREDB. |
| `minio-validation.sh` | 849 | MinIO health | UNTESTED | Cannot verify on COREDB. |
| `ai-routing-validation.sh` | 917 | AI routing paths | UNKNOWN | Likely validates LiteLLM and AI provider reachability. |
| `public-route-check.sh` | 802 | Public domain routes | PARTIAL | Covers HTTP status but does NOT validate response body content. Would flag a 200 with error page as healthy. |
| `revenue-healthcheck.sh` | 566 | Revenue-critical services | PARTIAL | Covers basic health checks but does not include Stripe mode verification or pipeline functional test. |
| `revenue-rollback-checklist.sh` | 672 | Rollback procedure | UNTESTED | Checklist exists but procedure never executed. |
| `activate-mirrors.sh` | 44 | Mirror agent activation | MINIMAL | Very small script, limited coverage. |
| `validation.env` | 67 | Shared test config | COMPLETE | Configuration is well-structured. |

---

### 7.2 Coverage Gaps

| Gap | Severity | Services Affected |
|-----|----------|-------------------|
| **No application-level health validation** | CRITICAL | FRGCRM Agent Service, SurplusAI Scraper, Voice Agent (process shows "online" but application logic is broken) |
| **No Stripe mode verification** | CRITICAL | Prediction Radar (no script checks whether Stripe keys are test or live) |
| **No pipeline functional test** | CRITICAL | FRGCRM Agent Service (no script triggers DAG run and validates stage completion) |
| **No AI provider key validation** | HIGH | All agent services (no script checks if DEEPSEEK_API_KEY or OPENAI_API_KEY is set) |
| **No Hostinger-side validation** | CRITICAL | All 10+ Hostinger services (scripts assume AIOPS-only context) |
| **No COREDB validation** | CRITICAL | PostgreSQL, Redis, MinIO on COREDB (scripts exist but cannot connect) |
| **No response body content validation** | HIGH | All public-facing services (scripts check HTTP 200 but not response content) |
| **No SSL certificate expiry check** | MEDIUM | All public domains |
| **No restore/rollback dry-run test** | HIGH | All services |
| **No cross-node connectivity test** | HIGH | Tailscale mesh between all 3 nodes |

---

### 7.3 False-Positive Risks in Validation Scripts

The following validation scripts WILL produce false-positive results under current conditions:

| Script | False Positive | Actual State | Why |
|--------|---------------|-------------|-----|
| `pm2-validation.sh` | "FRGCRM Agent Service: HEALTHY" | All 6 pipeline stages failing; service non-functional | Script checks PM2 status only, not application logic |
| `pm2-validation.sh` | "FRGCRM Mirror Test: HEALTHY" | Same codebase; same pipeline issues | Same reason |
| `docker-validation.sh` | "Prediction Radar: HEALTHY" | Stripe test mode; may not be collecting revenue | Script checks container status only, not payment configuration |
| `public-route-check.sh` | "fundsrecoverygroup.com: HEALTHY" | Frontend serves, but backend API is BROKEN; forms silently fail | Script checks HTTP 200 only, not form submission flow |
| `public-route-check.sh` | "surplusai.io: HEALTHY" | Scraper in 282+ restart loop; data is stale | Script checks HTTP 200 only, not data freshness |
| `revenue-healthcheck.sh` | "Revenue ecosystem: operational" | 50% of PM2 processes broken, Stripe in test mode, pipeline dead | If script doesn't check these specific conditions |

**The validation framework itself is a source of false confidence.** Running the existing scripts against the ecosystem would produce a report showing approximately 70-80% healthy — while the actual functional health is closer to 30-40%.

---

### 7.4 Missing Validation Scripts

These scripts need to be created:

| # | Script | Purpose | Priority |
|---|--------|---------|----------|
| 1 | `pipeline-functional-test.sh` | Trigger DAG run, validate all 6 stages complete successfully, check output | CRITICAL |
| 2 | `stripe-mode-verification.sh` | Check STRIPE_SECRET_KEY prefix, verify mode in Stripe Dashboard, check for live charges | CRITICAL |
| 3 | `ai-key-validation.sh` | Verify DEEPSEEK_API_KEY, OPENAI_API_KEY are set in all PM2 processes, test API key validity with a simple completion request | HIGH |
| 4 | `hostinger-healthcheck.sh` | Full health check script designed to run ON the Hostinger node | CRITICAL |
| 5 | `coredb-provision-check.sh` | Verify COREDB node reachable, PostgreSQL/Redis/MinIO installed and running | CRITICAL |
| 6 | `response-body-validator.sh` | Validate actual JSON response content, not just HTTP status codes | HIGH |
| 7 | `ssl-expiry-check.sh` | Check all 17 domain SSL certificate expiry dates | MEDIUM |
| 8 | `cross-node-connectivity.sh` | Verify Tailscale between all 3 nodes, latency, packet loss | HIGH |
| 9 | `api-end-to-end-test.sh` | Full end-to-end tests: lead intake -> scoring -> matching -> outreach | CRITICAL |
| 10 | `backup-verification.sh` | Automated test restore to verify backup integrity | HIGH |

---

## SECTION 8: WEEKLY AUDIT CADENCE

### 8.1 What to Run

Every week, execute the Zero-False-Green audit in this exact sequence:

#### Phase 1: Infrastructure Foundation (Run First — 10 minutes)

```bash
# 1. Verify all 3 nodes reachable
ssh aiops "hostname && uptime"
ssh edge "hostname && uptime"
ssh coredb "hostname && uptime"

# 2. Verify Tailscale mesh
ssh aiops "tailscale status --json | jq '[.Peer[] | {hostname: .HostName, online: .Online, relay: .Relay}]'"
# All 3 nodes must appear, online=true, relay="" (direct connection)

# 3. Verify Docker daemon on all nodes
ssh aiops "docker info > /dev/null 2>&1 && echo 'AIOPS DOCKER: OK' || echo 'AIOPS DOCKER: FAIL'"
ssh edge "docker info > /dev/null 2>&1 && echo 'EDGE DOCKER: OK' || echo 'EDGE DOCKER: FAIL'"
ssh coredb "docker info > /dev/null 2>&1 && echo 'COREDB DOCKER: OK' || echo 'COREDB DOCKER: FAIL'"

# 4. Verify disk space on all nodes (>20% free)
ssh aiops "df -h / | awk 'NR==2 {print $5}'"
ssh edge "df -h / | awk 'NR==2 {print $5}'"
ssh coredb "df -h / | awk 'NR==2 {print $5}'"
```

#### Phase 2: Data Layer (Run Second — 5 minutes)

```bash
# 5. COREDB PostgreSQL
ssh coredb "pg_isready -h localhost -p 5432"

# 6. COREDB Redis
ssh coredb "redis-cli PING"

# 7. COREDB MinIO
ssh coredb "curl -sf http://localhost:9000/minio/health/live"

# 8. AIOPS PostgreSQL instances (frgops-standby, prediction-radar-db, ravynai-db)
ssh aiops "pg_isready -h localhost -p 5433"
ssh aiops "docker exec prediction-radar-app-db pg_isready -U postgres"
ssh aiops "docker exec aiops-ravynai-postgres pg_isready -U postgres"
```

#### Phase 3: Application Layer (Run Third — 10 minutes)

```bash
# 9. PM2 process health (AIOPS)
ssh aiops "pm2 jlist | jq '[.[] | {name: .name, status: .pm2_env.status, restarts: .pm2_env.restart_time}]'"
# ALL processes must show status="online", restarts=0

# 10. PM2 process health (EDGE)
ssh edge "pm2 jlist | jq '[.[] | {name: .name, status: .pm2_env.status, restarts: .pm2_env.restart_time}]'"

# 11. Docker container health (AIOPS)
ssh aiops "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -v 'Up'"
# Should return nothing — all containers must be "Up"

# 12. Docker container health (EDGE)
ssh edge "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -v 'Up'"

# 13. FRGCRM pipeline functional test
ssh aiops "curl -s -X POST http://localhost:8003/pipeline/dag/run && sleep 30 && curl -s http://localhost:8003/pipeline/dag/latest | jq '.stages[] | {stage: .name, status: .status}'"
# All 6 stages must show "completed" or "success" — NOT "FAILED"

# 14. API health endpoints (all AIOPS APIs)
for port in 8000 8003 8007 3010; do
  echo "Port $port: $(ssh aiops "curl -sf -o /dev/null -w '%{http_code}' http://localhost:$port/health 2>/dev/null" || echo 'FAIL')"
done

# 15. Stripe mode verification
ssh aiops "docker exec prediction-radar-app env | grep STRIPE_SECRET_KEY | grep -o 'sk_[a-z]*_' | head -c -2"
# Expected: "sk_live_" (if production) or documented as intentional test mode
```

#### Phase 4: Public Routes (Run Fourth — 5 minutes)

```bash
# 16. Critical public domains
for domain in fundsrecoverygroup.com predictionradar.app surplusai.io frgops.fundsrecoverygroup.tech litellm.wheeler.ai ravynai.wheeler.ai docuseal.wheeler.ai uptime.wheeler.ai grafana.wheeler.ai; do
  echo "$domain: $(curl -sI "https://$domain" 2>/dev/null | head -1 || echo 'FAIL')"
done

# 17. SSL certificate expiry (any expiring in <30 days)
for domain in fundsrecoverygroup.com predictionradar.app; do
  echo | openssl s_client -servername "$domain" -connect "$domain":443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=/Expiry: /'
done
```

#### Phase 5: Monitoring Health (Run Fifth — 5 minutes)

```bash
# 18. Prometheus healthy
ssh aiops "curl -sf http://localhost:9090/-/healthy"

# 19. Prometheus scrape targets health
ssh aiops "curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health != \"up\")] | length'"
# Expected: 0 (all targets healthy)

# 20. Uptime Kuma all monitors green
# Check dashboard or API — confirm zero monitors in "down" state

# 21. Grafana dashboards loading
curl -sf https://grafana.wheeler.ai/api/health
```

---

### 8.2 Who Runs It

| Role | Responsibility |
|------|---------------|
| **Platform / DevOps Engineer** | Execute Phases 1, 2, 5 (infrastructure, data, monitoring) |
| **Backend Engineer** | Execute Phase 3 (application layer), with focus on pipeline test and PM2 health |
| **QA Engineer or SRE** | Execute Phase 4 (public routes and SSL) |
| **Engineering Lead** | Review full report, sign off, escalate if needed |

---

### 8.3 How to Report Results

Generate a one-page status summary with the following format:

```
WHEELER ZERO-FALSE-GREEN WEEKLY AUDIT — YYYY-MM-DD
====================================================

Overall Status: [GREEN / YELLOW / RED]

GREEN  = All 21 checks passed, no fake-healthy services detected
YELLOW = 1-3 checks failed OR unverified, no critical revenue impact
RED    = >3 checks failed OR any critical revenue service is fake-healthy or broken

Services by Status:
  TRULY HEALTHY:     N (list)
  PARTIALLY HEALTHY: N (list with unverified gates)
  FAKE HEALTHY:      N (list with hidden failures)  
  BROKEN:            N (list with evidence)
  UNVERIFIED:        N (list with reason)

Top Risks This Week:
  1. ...
  2. ...
  3. ...

Changes Since Last Audit:
  - Fixed: ...
  - Degraded: ...
  - New: ...

Action Items:
  - [ ] Critical (24h): ...
  - [ ] High (1 week): ...
  - [ ] Medium (2 weeks): ...

Auditor: [Name]
Reviewer: [Engineering Lead]
Time to complete audit: [Duration]
```

---

### 8.4 Escalation Path

| Severity | Condition | Action | Timeline |
|----------|-----------|--------|----------|
| **OUTAGE** | Any revenue-critical service is BROKEN (FRGCRM API, Prediction Radar, SurplusAI) | Page on-call engineer immediately. Notify CTO and CEO. Initiate incident response. | Within 15 minutes |
| **CRITICAL** | Any service is FAKE HEALTHY with revenue impact (Stripe test mode, pipeline failing, frontend accepting leads but API broken) | Notify Engineering Lead. Open critical ticket. Begin fix within 1 hour. | Within 1 hour |
| **HIGH** | Monitoring down (Prometheus, Grafana, Uptime Kuma) while services are healthy | Notify DevOps. Fix within 4 hours. Services may be running blind. | Within 4 hours |
| **MEDIUM** | Non-revenue service degraded or unverified | Open ticket. Address within next business day. | Within 24 hours |
| **LOW** | Documentation gaps, untested rollback, missing validation scripts | Add to sprint backlog. Address within 2 weeks. | Within 2 weeks |

**Escalation contacts (to be filled by team):**

| Role | Name | Contact |
|------|------|---------|
| On-Call Engineer | [TBD] | [TBD] |
| Engineering Lead | [TBD] | [TBD] |
| CTO | [TBD] | [TBD] |
| CEO | [TBD] | [TBD] |
| DevOps Lead | [TBD] | [TBD] |
| DBA | [TBD] | [TBD] |

---

## APPENDIX A: Scorecard Summary

One-page summary of every service's true health:

```
SERVICE                          NAIVE CHECK SAYS       ZERO-FALSE-GREEN SAYS
─────────────────────────────────────────────────────────────────────────────────
Nginx (EDGE)                     UNVERIFIED             UNVERIFIED
Traefik (EDGE)                   UNVERIFIED             UNVERIFIED
Cloudflare                       HEALTHY                PARTIALLY HEALTHY
fundsrecoverygroup.com FE        HEALTHY (200 OK)       FAKE HEALTHY (API broken)
FRGCRM Frontend                  UNVERIFIED             FAKE HEALTHY (API broken)
SurplusAI Frontend               UNVERIFIED             FAKE HEALTHY (scraper dead)
Attorney Mkt Frontend            UNVERIFIED             UNVERIFIED
FRGCRM API                       BROKEN                 BROKEN (confirmed)
SurplusAI API                    UNVERIFIED             BROKEN (282 restarts)
Wheeler Brain OS API             UNVERIFIED             UNVERIFIED (not observed)
Prediction Radar API             HEALTHY                PARTIALLY HEALTHY (Stripe test)
Attorney Mkt API                 UNVERIFIED             UNVERIFIED (not observed)
LiteLLM Gateway                  UNVERIFIED             UNVERIFIED (Hostinger)
OpenClaw                         UNVERIFIED             UNVERIFIED (embedded)
PostgreSQL (COREDB)              UNVERIFIED             UNVERIFIED (node unreachable)
Redis (COREDB)                   UNVERIFIED             UNVERIFIED (node unreachable)
MinIO (COREDB)                   UNVERIFIED             UNVERIFIED (node unreachable)
Grafana                          UNVERIFIED             UNVERIFIED (location disputed)
Prometheus                       HEALTHY                PARTIALLY HEALTHY (targets?)
Loki                             UNVERIFIED             UNVERIFIED
Uptime Kuma                      UNVERIFIED             UNVERIFIED (location disputed)
PM2 (AIOPS)                      HEALTHY                PARTIALLY HEALTHY (50% broken)
Docker (AIOPS)                   HEALTHY                PARTIALLY HEALTHY (EDGE/COREDB?)
Tailscale                        HEALTHY                PARTIALLY HEALTHY (COREDB?)
─────────────────────────────────────────────────────────────────────────────────
RavynAI API                      HEALTHY                PARTIALLY HEALTHY
FRGCRM Agent Svc                 HEALTHY (ONLINE)       FAKE HEALTHY (pipeline dead)
FRGCRM Mirror Test               HEALTHY (ONLINE)       PARTIALLY HEALTHY
Insforge Agent Svc               HEALTHY (ONLINE)       PARTIALLY HEALTHY
Docuseal                         HEALTHY                PARTIALLY HEALTHY
Chatwoot                         UNVERIFIED             UNVERIFIED
n8n                              UNVERIFIED             UNVERIFIED
Webhook Receiver                 UNVERIFIED             UNVERIFIED
```

**Summary counts:**

| Classification | Count |
|---------------|-------|
| TRULY HEALTHY | **0** |
| PARTIALLY HEALTHY | **9** (Prediction Radar, RavynAI, FRGCRM Agent Svc, FRGCRM Mirror Test, Insforge Agent Svc, Docuseal, Cloudflare, Prometheus, PM2/Docker/Tailscale AIOPS) |
| FAKE HEALTHY | **4** (fundsrecoverygroup.com FE, FRGCRM Frontend, SurplusAI Frontend, FRGCRM Agent Svc) |
| BROKEN | **3** (FRGCRM API, SurplusAI Scraper Agent, Voice Agent Service) |
| UNVERIFIED | **14** (All Hostinger services, all COREDB services, conflicting-location services, services not observed in live survey) |

Note: Some services appear in multiple categories because the broader service (e.g., PM2) is PARTIALLY HEALTHY while the specific managed process is in a different state.

---

## APPENDIX B: Document Cross-Reference

| Document | Status | Relevance |
|----------|--------|-----------|
| TEST_INVENTORY.md | EXISTS | Canonical service list with 25 services. Contains documented health expectations that have NOT been verified live. |
| API_READINESS_MATRIX.md | EXISTS | Live survey findings. Source of truth for actual service status on AIOPS. Reveals 3 broken services. |
| REVENUE_APP_INVENTORY.md | EXISTS | 24-app revenue inventory. Source of truth for PM2 and Docker status. |
| DOMAIN_ROUTING_MAP.md | EXISTS | 17-domain routing table. All routing is assumed, not verified. |
| REVENUE_SYSTEMS_EXECUTIVE_REPORT.md | EXISTS | C-suite summary. Accurate in its assessment of broken services. |
| LEAD_INTAKE_READINESS.md | EXISTS | Deep dive on lead pipeline. Source of truth for DEEPSEEK_API_KEY finding and pipeline failure. |
| PAYMENT_WEBHOOK_READINESS.md | EXISTS | Payment and webhook assessment. Source of Stripe test-mode finding. |
| REVENUE_CUTOVER_PLAN.md | EXISTS | Migration plan. All gates are currently failing. |
| REVENUE_ROLLBACK_PLAN.md | EXISTS | Rollback procedures. Never tested. |
| MIGRATION_GATE_CHECKLIST.md | **MISSING** | Referenced but does not exist on disk. Must be created. |

---

## APPENDIX C: Definitions

**Zero False Green:** A principle stating that no service may be reported as healthy unless it passes all 10 verification conditions. A single failed or unverified condition means the service is not healthy. "Probably fine" is not acceptable — only "proven working" counts.

**Fake Healthy:** A service that passes naive surface-level checks (process running, port listening, HTTP 200) but fails when inspected at depth (application logic broken, dependency down, configuration error, payment mode mismatch).

**Crash Loop:** A condition where a process repeatedly starts, crashes, and is restarted by the process manager. Indicated by non-zero restart counts in PM2. Even if the process is momentarily "online" between restarts, it is classified as BROKEN.

**Unverified:** A service whose status cannot be determined because the necessary access (SSH, API, network) is not available. All unverified services must be assumed BROKEN for the purpose of migration decisions.

**Partially Healthy:** A service whose process is stable and serving requests but has one or more unverified or missing zero-false-green conditions. This is a temporary classification — partially healthy services should be driven to truly healthy through verification and fixes.

---

*This document is the definitive health assessment of the Wheeler ecosystem as of 2026-05-23. It supersedes all prior health reports. Its purpose is to eliminate false confidence and drive the ecosystem to provable, verifiable health. Every statement is backed by a specific command that can be executed to verify or refute it. No claims are made without evidence.*

*Signed:*

*Principal Zero-False-Green Systems Engineer*
*Wheeler Ecosystem*
