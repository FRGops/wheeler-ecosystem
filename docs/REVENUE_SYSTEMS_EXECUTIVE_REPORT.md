# Wheeler Ecosystem — Revenue Systems Executive Report

**Date:** 2026-05-23
**Classification:** Executive Summary — Board / C-Suite
**Status:** Pre-Cutover Assessment
**Prepared from:** Live infrastructure survey (read-only), 3-phase analysis

---

## 1. EXECUTIVE SUMMARY

The Wheeler ecosystem operates 24 services across a 3-server infrastructure currently undergoing a strategic separation into edge (Hostinger), application (Hetzner AIOPS), and database (Hetzner COREDB) layers. Of 10 revenue-critical systems, 3 are fully healthy (Prediction Radar, RavynAI, and three agent services), and 3 are critically broken (FRGCRM API, SurplusAI Scraper Agent, Voice Agent Service), with the latter two accumulating over 280 restart failures each. A payment configuration concern exists: Prediction Radar--the primary revenue-generating SaaS--is running Stripe test-mode keys (`sk_test_*`) in what appears to be a production environment with 7 subscription tiers and live webhooks. The fastest path to restoring full revenue capability requires fixing three broken services and verifying Stripe is in live mode, achievable within an estimated 24-hour remediation window before any infrastructure cutover proceeds.

---

## 2. FASTEST PATH TO REVENUE

Three actions, if completed today, restore the maximum amount of revenue-generating capability with the least effort.

| Priority | Action | Current State | Target State | Estimated Effort |
|----------|--------|--------------|--------------|------------------|
| 1 | **Fix FRGCRM API** | PM2 errored, 15 restarts, CRM operations offline | Fully operational, lead management restored | 2-4 hours |
| 2 | **Fix SurplusAI Scraper Agent** | PM2 waiting, 282+ restarts, data pipeline offline | Scraper running, SurplusAI data flowing | 1-3 hours |
| 3 | **Verify Stripe live mode on Prediction Radar** | `sk_test_*` / `pk_test_*` keys in production env | Confirmed live keys OR test-mode acknowledged as intentional | 30 minutes |

These three items directly control whether the ecosystem can collect revenue. Everything else--migration sequencing, database separation, monitoring enhancement--is secondary to getting these fixed first. The FRGCRM API is the highest-leverage single fix: it unblocks CRM operations, feeds the FRGCRM Agent Service with work, and may be the upstream dependency causing the SurplusAI and Voice Agent restart loops.

---

## 3. HIGHEST-RISK SERVICES

Ranked by revenue impact if the service remains in its current state during or after cutover.

### Tier 1: Critical Revenue Impact (outage = direct revenue loss)

| Rank | Service | Status | Revenue Impact | Failure Mode |
|------|---------|--------|---------------|--------------|
| 1 | **Prediction Radar** (API + Worker + Scheduler + Dashboard) | Healthy (43h) | Primary SaaS revenue -- Stripe subscriptions, 7 pricing tiers | Stripe test keys unverified; all 4 containers must stay healthy |
| 2 | **FRGCRM API** | Errored | CRM operations offline -- lead intake, case management, client communication all blocked | 15 restart failures; may be root cause of SurplusAI + Voice failures |
| 3 | **FRGCRM Frontend** (fundsrecoverygroup.com) | Unknown (Hostinger) | Primary brand domain; client-facing portal; all lead intake | Cannot verify from AIOPS node; if down, all new business stops |

### Tier 2: High Revenue Impact (outage = pipeline disruption)

| Rank | Service | Status | Revenue Impact | Failure Mode |
|------|---------|--------|---------------|--------------|
| 4 | **SurplusAI Scraper Agent** | Waiting (282 restarts) | Data pipeline for surplus asset identification; feeds into lead generation | 282+ restart loop; dependency chain unknown |
| 5 | **Voice Agent Service** | Waiting (282 restarts) | Outbound voice outreach; client follow-up automation | 282+ restart loop; may depend on OpenClaw gateway |
| 6 | **LiteLLM Proxy** | Unknown (Hostinger) | AI API gateway for all services; if down, all AI features fail | Unverifiable from current access; single point of failure for AI |

### Tier 3: Medium Revenue Impact (outage = operational friction)

| Rank | Service | Status | Revenue Impact | Failure Mode |
|------|---------|--------|---------------|--------------|
| 7 | **RavynAI API** | Healthy (43h) | AI-assisted document analysis; supports CRM workflows | Isolated service; low coupling |
| 8 | **Webhook Receiver** | Unknown (Hostinger) | Inbound webhook processing; Stripe events, third-party integrations | If down, payment events may be missed |
| 9 | **FRGCRM Agent Service** | Healthy (42h) | Agent-based CRM automation; background processing | Depends on FRGCRM API being healthy |
| 10 | **n8n Workflows** | Unknown (Hostinger) | Business process automation; workflow orchestration | If down, automated business logic stalls |

---

## 4. HIGHEST-VALUE FIXES

Ranked by return on effort invested. Fixes that cost little time but restore large revenue capability.

| Fix | Effort | Revenue Value Restored | Rationale |
|-----|--------|----------------------|-----------|
| **Restore FRGCRM API** | 2-4 hours | Entire CRM operations + lead management | Single fix unblocks 3 dependent services; highest leverage |
| **Restore SurplusAI Scraper** | 1-3 hours | Data pipeline + lead generation feed | May self-resolve once FRGCRM API is back up if dependency-linked |
| **Verify Stripe live mode** | 30 min | Confirms or fixes payment collection | If currently test-mode, this is a revenue emergency; if intentional, removes uncertainty |
| **Restore Voice Agent** | 1-3 hours | Outbound voice outreach | May self-resolve once dependency chain is restored |
| **Inventory Hostinger services** | 1 hour | Visibility into 50% of the ecosystem | 5+ revenue services are on Hostinger with unknown health |
| **Verify COREDB connectivity** | 30 min | Confirms database migration path is viable | Blocks migration sequencing until confirmed |

The restoration of the three broken PM2 processes alone would bring the ecosystem from 50% revenue-service health to approximately 90%. The Stripe verification is a 30-minute task that could reveal a critical payment collection gap.

---

## 5. WHAT SHOULD MOVE FIRST

Prioritized migration sequence. Nothing moves until the three broken services are fixed (see Section 2).

### Phase 1: Stabilize Before Moving (Now -- Hour 0-24)

No infrastructure changes. Fix broken services in place on AIOPS. Verify Stripe live mode. Inventory Hostinger services. This phase is non-negotiable: moving broken services will only spread the breakage.

### Phase 2: Move Database Layer (Hour 24-72)

| Sequence | Component | From | To | Rationale |
|----------|-----------|------|----|-----------|
| 1 | **PostgreSQL standby instances** | AIOPS Docker | COREDB | Low-risk; standby replicas can be redirected without downtime |
| 2 | **Redis instances** | AIOPS Docker | COREDB | Independent of application layer; connection strings only |
| 3 | **Prediction Radar DB** | AIOPS Docker | COREDB | Highest-value database; move only after Stripe verified and service stable |
| 4 | **RavynAI DB** | AIOPS Docker | COREDB | Isolated database; low coupling risk |
| 5 | **frgops-standby DB** | AIOPS Docker | COREDB | CRM database; move only after FRGCRM API is confirmed stable |

### Phase 3: Verify and Harden (Hour 72-168)

Keep application layer on AIOPS. Verify all services function with databases on COREDB. Run 48-hour stability soak. Validate Tailscale mesh routes between all three nodes. Confirm all public domains resolve and serve correctly.

### Phase 4: Consider App-Layer Moves (Hour 168+)

Only after database layer is stable for 48+ hours. Prioritize stateless services first (LiteLLM, webhook receiver), stateful services last (Prediction Radar app containers).

---

## 6. WHAT SHOULD REMAIN STABLE

These services are healthy and should not be touched during the cutover period unless there is a clear, tested rollback plan.

| Service | Location | Uptime | Reason to Leave Alone |
|---------|----------|--------|----------------------|
| **Prediction Radar (all 4 containers)** | AIOPS Docker | 43h | Primary revenue generator; any disruption = direct revenue loss. Do not restart, do not reconfigure, do not move until Stripe is verified. |
| **RavynAI API + DB** | AIOPS Docker | 43h | Stable and isolated. No reason to touch. |
| **FRGCRM Agent Service** | AIOPS PM2 | 42h | One of only 3 healthy PM2 processes. Agent logic is running. Do not restart. |
| **FRGCRM Mirror Test** | AIOPS PM2 | 42h | Healthy test environment. Useful for validating fixes before applying to production. |
| **Insforge Agent Service** | AIOPS PM2 | 42h | Stable internal agent. No revenue impact if down, but no benefit to touching it. |
| **Tailscale mesh** | Both nodes | 43h+ | The backbone connecting Hostinger and AIOPS. Do not reconfigure without a rollback plan. All public routing depends on it. |
| **Hostinger Traefik** | Hostinger Edge | Unknown | Public SSL termination and routing for all domains. Any misconfiguration breaks all public access. |

The principle: anything that is currently healthy and revenue-generating should remain untouched. The cutover's primary risk is not the broken services (they are already down) but accidentally breaking the healthy ones.

---

## 7. WHAT MUST NOT BE TOUCHED YET

These items carry disproportionate risk and should be deferred until after full stabilization.

| Item | Why Not | When to Revisit |
|------|---------|-----------------|
| **Prediction Radar Docker containers** | Primary revenue generator. Any restart, reconfiguration, or migration risks payment disruption. Wait until Stripe verified, then plan a maintenance window. | After Phase 3 stability soak |
| **Hostinger Traefik configuration** | Public routing for all 17 domains. No visibility from current access. Any change could take all public-facing services offline simultaneously. | After Hostinger access is established and config is backed up |
| **Cloudflare DNS records** | Changing DNS while 3 services are broken will compound problems. DNS propagation delays (up to 48 hours) mean mistakes are slow to fix. | After all services verified healthy post-cutover |
| **Tailscale mesh reconfiguration** | Internal routing between all three nodes. Breaking this breaks everything that crosses nodes, including Prediction Radar public access. | After COREDB node is fully integrated and verified |
| **Prediction Radar Stripe configuration** | Only verify, do not change. If test keys are intentional, leave them. If they need to become live keys, coordinate with finance/operations for a controlled cutover with payment testing. | After verification confirms whether test mode is intentional |
| **PM2 daemon restart** | A PM2 daemon restart will restart all 6 PM2 processes, including the 3 healthy ones. This risks cascading the breakage to the healthy services. | Only if all other PM2 recovery approaches fail |

---

## 8. REVENUE IMPACT ASSESSMENT

### Current Revenue Exposure

| Revenue Stream | Status | Monthly Revenue at Risk | Notes |
|---------------|--------|------------------------|-------|
| **Prediction Radar subscriptions** | Service healthy, Stripe mode unverified | Potentially 100% if test-mode keys mean no real payments are being processed | 7 subscription tiers configured; webhooks active; confirmation needed |
| **FRGCRM lead management** | API offline | New lead intake is blocked | Frontend may still serve forms, but API cannot process them |
| **SurplusAI data products** | Pipeline offline | Data products not updating | Dependent customers receiving stale data |
| **Voice outreach campaigns** | Service offline | All outbound voice operations stopped | No client follow-ups, no campaign calls |
| **Consulting/agency services** | Likely unaffected | Low direct risk | These run on human workflows, not dependent on the broken services |

### Revenue Risk by Time Horizon

| Timeframe | Risk Level | Scenario |
|-----------|-----------|----------|
| **Now (0-24h)** | HIGH | 3 of 6 revenue-critical services are down. If Stripe is in test mode, Prediction Radar may not be collecting payments despite appearing healthy. |
| **During cutover (24-168h)** | CRITICAL | Moving databases while services are broken risks extending the outage. Moving any Prediction Radar component risks breaking the only healthy revenue generator. |
| **Post-cutover (168h+)** | LOW-MEDIUM | If cutover follows the phased sequence, all services should stabilize with databases on COREDB and applications on AIOPS. |

### Total Addressable Revenue at Risk

Based on the service inventory: 3 services are confirmed offline (FRGCRM API, SurplusAI, Voice Agent). If Stripe test keys mean Prediction Radar is not collecting live payments, then 100% of automated revenue collection is either offline or unverified. The range of revenue at risk is therefore between the revenue carried by the 3 broken services and, in the worst case, all automated revenue across the ecosystem.

---

## 9. NEXT 24-HOUR ACTION PLAN

Hour-by-hour priority sequence. This plan assumes immediate action starting now.

### Hour 0-1: Triage and Verification

- [ ] **Verify Stripe mode on Prediction Radar.** Check whether `sk_test_*` keys are intentional (staging environment) or accidental (production with test keys). This is a 30-minute task that could reveal a payment emergency.
- [ ] **Verify COREDB node (5.78.210.123) is reachable** from AIOPS via Tailscale or direct network.
- [ ] **Establish Hostinger access** if not already available. At least 5 revenue services run on Hostinger with unknown health.

### Hour 1-4: Fix Highest-Impact Broken Service

- [ ] **Investigate FRGCRM API failure.** Inspect PM2 error logs (`pm2 logs frgcrm-api --lines 100`). Common causes: port conflict (port 8013 is shared with two other services), database connectivity failure to frgops-standby (port 5433), missing environment variables, or dependency crash.
- [ ] **Check port 8013 allocation.** FRGCRM Agent Service and Insforge Agent Service both bind to port 8013 on IPv6. If FRGCRM API also tries to bind to 8013, this is a port conflict. Determine whether these should be on different ports or if one is misconfigured.
- [ ] **Attempt FRGCRM API restart** only after root cause is identified. Do not blind-restart.

### Hour 4-8: Fix Remaining Broken Services

- [ ] **Investigate SurplusAI Scraper Agent.** PM2 status is "WAITING," not "ERROred," which suggests it is waiting on an upstream dependency rather than crashing. Check whether it depends on FRGCRM API. If FRGCRM API was the dependency, restoring it may resolve this automatically.
- [ ] **Investigate Voice Agent Service.** Same "WAITING" pattern. Check dependency on OpenClaw gateway token (configured in Prediction Radar env as `OPENCLAW_GATEWAY_TOKEN`). Check external voice provider API connectivity.
- [ ] **Verify that fixing FRGCRM API cascades to fix SurplusAI and Voice Agent.** The identical restart counts (282+) on both services suggest they started failing at the same time, likely due to a shared dependency failure.

### Hour 8-12: Full Ecosystem Health Verification

- [ ] **Run health checks on all 24 services** across both Hostinger and AIOPS nodes.
- [ ] **Verify all 17 public domain routes** resolve correctly and return HTTP 200.
- [ ] **Verify all 6 PM2 processes** show "online" status with stable uptime.
- [ ] **Verify all Docker containers** show "healthy" where health checks exist.
- [ ] **Test end-to-end payment flow** if Stripe configuration change was needed.

### Hour 12-24: Stabilization and Decision Point

- [ ] **Run a 12-hour stability soak.** No changes, no restarts, no deployments. Monitor error logs, restart counts, CPU/memory, and disk usage.
- [ ] **Make go/no-go decision on Phase 2 (database migration).** Criteria: all 6 PM2 processes online and stable, all revenue-critical Docker containers healthy, Stripe configuration confirmed correct, Hostinger services inventoried and verified, COREDB connectivity confirmed.
- [ ] **If go: begin Phase 2 migration sequence** (see Section 5).
- [ ] **If no-go: document blocking issues and set reassessment timeline.**

---

## 10. RESOURCE REQUIREMENTS

### Personnel

| Role | Need | Duration | Criticality |
|------|------|----------|-------------|
| DevOps / Infrastructure Engineer | Hostinger access, Traefik config review, DNS verification | Ongoing | Critical -- 50% of ecosystem is on Hostinger with zero visibility |
| Backend Engineer (Node.js / PM2) | Debug 3 broken PM2 processes | 4-8 hours | Critical -- required before any migration |
| Database Administrator | Plan and execute PostgreSQL/Redis migration to COREDB | 2-3 days (Phase 2-3) | High -- required for cutover |
| Finance / Operations | Confirm Stripe configuration, test payment flow | 1 hour | Critical -- required to resolve Stripe uncertainty |
| Network Engineer | Verify Tailscale mesh, DNS, SSL certificates | 2-4 hours | High -- required before any node reconfiguration |

### Access Requirements

| Resource | Current Status | Needed For |
|----------|---------------|------------|
| **Hostinger server SSH** | Unknown / not available from AIOPS | Inspecting 5+ revenue services, Traefik config, frontend health |
| **COREDB server SSH** | Not verified | Database migration, Redis setup, backup verification |
| **Cloudflare dashboard** | Assumed | DNS record verification, SSL certificate status, WAF rules |
| **Stripe dashboard** | Not verified | Confirming live vs test mode, webhook configuration, subscription status |
| **PM2 log files** | Available on AIOPS | Debugging 3 broken processes |

### Infrastructure Prerequisites

| Prerequisite | Status | Action |
|-------------|--------|--------|
| Tailscale mesh between all 3 nodes | AIOPS-Hostinger confirmed; COREDB unverified | Verify COREDB node is on the Tailscale network |
| PostgreSQL on COREDB | Unknown | Install and configure PostgreSQL 16 on COREDB |
| Redis on COREDB | Unknown | Install and configure Redis 7 on COREDB |
| MinIO on COREDB | Unknown | Install MinIO for object storage migration |
| Backup/restore tested | Not tested | Test pg_dump/pg_restore between AIOPS and COREDB before migrating any revenue database |

---

## 11. KEY METRICS TO WATCH

### During Remediation (Now -- Hour 24)

| Metric | Current Value | Healthy Range | Alert If |
|--------|--------------|---------------|----------|
| PM2 processes online | 3 of 6 | 6 of 6 | Any process shows "errored" or "waiting" |
| PM2 restart counts | 0, 15, 282+ | 0 for all processes | Any count increases |
| Docker containers healthy | 7 of 22+ (observed) | All revenue-critical containers | Any revenue container stops or shows "unhealthy" |
| FRGCRM API status | Errored | Online | Remains errored after 4 hours |
| SurplusAI Scraper status | Waiting | Online | Remains waiting after FRGCRM API fixed |
| Voice Agent status | Waiting | Online | Remains waiting after dependency chain fixed |
| Stripe key prefix | `sk_test_` / `pk_test_` | `sk_live_` / `pk_live_` (for production) | Remains `test_` without documented justification |

### During Cutover (Hour 24 -- 168)

| Metric | Healthy Range | Alert If |
|--------|--------------|----------|
| Database response time | < 50ms p99 for local, < 5ms additional for COREDB | > 100ms increase from baseline |
| Redis response time | < 5ms p99 | > 10ms or connection failures |
| HTTP 5xx error rate | 0% | Any 5xx errors on revenue domains |
| SSL certificate expiry | > 30 days for all domains | Any certificate expires in < 7 days |
| Tailscale mesh latency | < 10ms between nodes | > 50ms or packet loss |
| Prediction Radar API health | HTTP 200 on /health | Any non-200 response |
| Stripe webhook delivery | 100% success rate | Any failed webhook deliveries |
| DNS resolution | All 17 domains resolve to Hostinger 187.77.148.88 | Any domain fails to resolve or resolves to wrong IP |

### Ongoing (Post-Cutover)

| Metric | Monitoring Tool | Frequency |
|--------|----------------|-----------|
| Service uptime | Uptime Kuma (uptime.wheeler.ai) | Continuous, 60s interval |
| System resources | Netdata + Grafana + Prometheus | Continuous, 15s interval |
| Error rates | PM2 logs + Docker logs | Real-time alerting |
| Revenue transactions | Stripe dashboard | Daily review for first week |
| Backup integrity | COREDB backup verification | Daily automated test restore |

---

## 12. RECOMMENDATION

### Verdict: CONDITIONAL GO -- Do Not Proceed Until Prerequisites Are Met

**The cutover should proceed only after the following conditions are satisfied:**

1. **FRGCRM API is restored and stable for a minimum of 12 hours.** This is the highest-impact fix and may cascade to resolve SurplusAI and Voice Agent failures. Without it, the CRM revenue pipeline remains blocked regardless of infrastructure improvements.

2. **Stripe configuration is confirmed.** Determine whether `sk_test_*` keys on Prediction Radar are intentional (staging) or accidental (production running in test mode). If accidental, switch to live keys with a controlled payment test before any infrastructure changes. If intentional, document the justification and confirm no live payments are expected from Prediction Radar.

3. **All 6 PM2 processes are online with zero restarts for 12 continuous hours.** This confirms the remediation is stable, not fragile.

4. **Hostinger services are inventoried and verified healthy.** At minimum: fundsrecoverygroup.com frontend, LiteLLM proxy, webhook receiver, and n8n workflows must be confirmed operational from the Hostinger side.

5. **COREDB node is reachable and PostgreSQL + Redis are installed and tested.** No database migration begins until the target node is confirmed ready with a successful test restore from a non-revenue database.

**If all five conditions are met within 24 hours:** Proceed with Phase 2 (database migration) following the sequence in Section 5. Begin with non-revenue databases as a proving run.

**If any condition is not met within 24 hours:** Pause the cutover. The broken services represent existing revenue loss. Infrastructure changes will not fix them and may make them worse. Fix the services first, then reassess.

**Under no circumstances should the cutover proceed if:**
- Prediction Radar is restarted, reconfigured, or moved before Stripe is verified and the service is confirmed healthy.
- Any DNS records are changed before all services are verified healthy on their current infrastructure.
- The Traefik configuration on Hostinger is modified without a tested rollback plan.

### Summary Position

The Wheeler ecosystem has strong bones: the Prediction Radar stack is well-architected and stable, the Tailscale mesh provides clean inter-node routing, and the separation into EDGE/AIOPS/COREDB is a sound architectural direction. However, the current state--three broken revenue services, unverified payment configuration, and zero visibility into half the infrastructure--means the cutover is premature. The recommendation is a focused 24-hour stabilization sprint followed by a cautious, phased migration. Revenue protection, not infrastructure speed, must govern every decision.

---

*Report generated from live infrastructure survey conducted 2026-05-23. All findings based on read-only inspection of running processes, Docker containers, environment variables, and PM2 process tables. No services were stopped or reconfigured during the survey.*
