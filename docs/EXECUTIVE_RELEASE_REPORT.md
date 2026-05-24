# Wheeler Deployment & Release Engineering -- Executive Release Report

**Prepared by:** Wheeler Release Engineering
**Date:** 2026-05-23
**Classification:** INTERNAL -- Engineering Leadership / CTO / VP Engineering
**Version:** 2.0.0
**Supersedes:** v1.0 (EXECUTIVE_RELEASE_REPORT.md dated 2026-05-23)

---

## 1. Executive Summary

The Wheeler ecosystem operates 24 services across a three-server infrastructure (EDGE at Hostinger, AIOPS and COREDB at Hetzner) with a deployment maturity score of 1.4 out of 5.0 -- classifying it as **EARLY STAGE**. The current deployment process is predominantly manual (SSH + git pull + PM2 restart), creating material risk of human error, inconsistent environments, and slow incident recovery. The single biggest gap is the absence of automated rollback capability -- no service in the ecosystem has a tested, reliable path back to a known-good state after a failed deployment. This gap represents the highest-priority risk to address, with an estimated effort of 3-5 engineering-days. The phased rollout plan presented here achieves basic deployability safety (Phase 1: backups and health checks) within one week and full automated deployment maturity (Phase 4: canary releases and self-healing) within eight weeks, requiring approximately 21-28 person-days of focused effort.

---

## 2. Current Deployment Maturity Assessment

### 2.1 Maturity Radar (Text-Based)

```
                         Automated Deployment (1/5)
                                /\
                               /  \
                              /    \
             Rollback (1/5)  /      \  Monitoring (2/5)
                            /        \
                           /    ★     \
                          /   Current  \
                         /    State     \
         Backup (2/5)   /________________\  CI/CD (1/5)
                        \                /
                         \              /
         Env Mgmt (1/5)  \            /  Secret Mgmt (1/5)
                           \        /
                            \      /
                             \    /
                              \  /
                               \/
         Canary (1/5) -- DB Migration (1/5) -- DR (1/5)

  ★ = Current state -- 1.4/5 average across all dimensions
  Target state: all dimensions ≥ 4/5
```

The radar shape reveals an ecosystem that is uniformly weak across all dimensions. No single dimension is strong enough to compensate for the weaknesses elsewhere. The three dimensions rated 2/5 (Monitoring, Backup) represent areas where some ad-hoc capability exists but is not systematized or tested. All other dimensions are at 1/5, meaning either no capability exists or what exists is theoretical and untested.

### 2.2 Detailed Dimension Assessment

| Dimension | Rating | Evidence | Critical Gap |
|-----------|--------|----------|--------------|
| **Automated Deployment** | 1/5 | Manual SSH + pm2 restart is the standard. No deploy-service.sh in production use. No CI-triggered deploys. | No scripted deployment; every deploy is a handcrafted sequence of commands. |
| **Rollback Capability** | 1/5 | Manual git checkout of previous commit + pm2 restart. No backup-before-deploy. No rollback engine. | No tested rollback path exists for any of the 24 services. |
| **Monitoring & Observability** | 2/5 | PM2 monitoring exists. Basic health endpoints on some services (Prediction Radar, RavynAI, Docuseal, FRGCRM Agent). No centralized deployment dashboard. Grafana and Loki available but not configured for deployment monitoring. Uptime Kuma deployed for uptime tracking. | No deployment-specific monitoring (error rate diff, latency comparison). No alert on deploy failure. |
| **Backup Strategy** | 2/5 | Some database backups exist (PostgreSQL dump capabilities confirmed). No automated pre-deploy config backups. No backup verification or restoration testing. No backup retention policy enforced. | No service config backups, no environment file backups, no backup integrity checks. No off-server backup verification. |
| **CI/CD Pipeline** | 1/5 | No GitHub Actions workflows deployed in production. Builds and tests run locally on developer machines. No automated linting, testing, or build pipeline. | No automated build, test, lint, or deploy pipeline. Zero CI workflows active. |
| **Environment Management** | 1/5 | .env files exist but are inconsistent across servers. No naming standard. Evidence of duplicate DATABASE_URL definitions across services. No .env.example template. No validation of required variables. | No standardized naming convention, no validation, no template. Env drift between staging and production is likely. |
| **Secret Management** | 1/5 | Secrets hardcoded in .env files on servers. Stripe test keys (sk_test_*) found in Prediction Radar production environment. No secrets manager integration. No secret rotation. No audit trail. | Secrets in plaintext on disk. No rotation mechanism. No secret scanning in CI. |
| **Database Migration Safety** | 1/5 | No formal migration process. Alembic is available but no backup-before-migration workflow exists. No staging validation required. No downgrade path testing. | No staged migration flow, no auto-rollback of failed migrations, no pre-migration backup mandate. |
| **Canary Capability** | 1/5 | No canary deployment infrastructure. Traefik supports weighted routing on EDGE but is not configured for canary traffic splitting. All deployments are all-at-once. | No traffic splitting mechanism configured. No gradual rollout capability for any service. |
| **Disaster Recovery** | 1/5 | No documented DR procedure. No tested restore from backup. Server separation provides some physical redundancy but no procedure exists for failing over between nodes. | No DR runbook. Backups exist but have never been restored in a drill. No RTO/RPO defined. |

**Overall Maturity Score: 1.4 / 5.0 -- EARLY STAGE**

### 2.3 Trend Analysis

| Dimension | Current (May 2026) | 3-Month Target (Aug 2026) | Gap |
|-----------|-------------------|--------------------------|-----|
| Automated Deployment | 1/5 | 4/5 | +3 |
| Rollback Capability | 1/5 | 5/5 | +4 |
| Monitoring & Observability | 2/5 | 4/5 | +2 |
| Backup Strategy | 2/5 | 5/5 | +3 |
| CI/CD Pipeline | 1/5 | 4/5 | +3 |
| Environment Management | 1/5 | 4/5 | +3 |
| Secret Management | 1/5 | 3/5 | +2 |
| DB Migration Safety | 1/5 | 4/5 | +3 |
| Canary Capability | 1/5 | 4/5 | +3 |
| Disaster Recovery | 1/5 | 3/5 | +2 |

The heaviest lifts are Rollback Capability (+4) and several dimensions requiring +3 improvement. Secret Management and Disaster Recovery are rated to reach 3/5 rather than 4-5/5 because full secrets management (Doppler/Hashicorp Vault) and full DR testing require organizational decisions beyond the scope of the engineering team alone.

---

## 3. Biggest Deployment Risks

### 3.1 Risk Matrix (Impact x Likelihood)

| # | Risk | Impact | Likelihood | Score | Current Mitigation |
|---|------|--------|------------|-------|-------------------|
| 1 | Failed deployment with no tested rollback | Critical | High | **CRITICAL** | None |
| 2 | Environment variable misconfiguration | High | High | **CRITICAL** | Manual review only |
| 3 | Database data loss during migration | Critical | Medium | **HIGH** | No pre-migration backup |
| 4 | Secret exposure in logs or configs | Critical | Medium | **HIGH** | .gitignore only |
| 5 | Production outage from PM2 restart loop | High | Medium | **HIGH** | PM2 max_restarts (10 in 60s) |
| 6 | Cross-server config drift | Medium | High | **MEDIUM** | None |
| 7 | AI model routing failure during deploy | High | Low | **MEDIUM** | Circuit breaker planned |

### 3.2 Detailed Risk Analysis

#### Risk 1: Failed Deployment with No Tested Rollback

- **Description:** A deployment introduces a bug (config error, code regression, dependency mismatch). The service crashes or behaves incorrectly. There is no automated or tested way to restore the previous working version. The operator must manually reconstruct the previous state under incident pressure, likely making errors.
- **Impact:** Critical -- production service down with unknown recovery time. For revenue-critical services (Prediction Radar, FRGCRM API), this directly impacts revenue.
- **Likelihood:** High -- manual deployments are inherently error-prone. With no validation gates, a bad deploy reaches production undetected.
- **What could go wrong:** Operator fat-fingers a command during rollback, making the situation worse. Backup is found to be corrupted. Previous version has a different dependency set that no longer installs cleanly. Recovery takes hours instead of minutes.
- **Current mitigation:** None. Rollback is entirely manual and untested.
- **Recommended mitigation:** 
  1. Implement mandatory pre-deploy backup (configs, code, env files) 
  2. Build `/root/rollback-engine/rollback.sh` with service-type awareness (PM2, Docker, static)
  3. Test rollback on staging weekly for all service types
  4. Time every rollback; target < 2 minutes from trigger to healthy
- **Effort to fix:** M (3-5 engineering-days)

#### Risk 2: Environment Variable Misconfiguration

- **Description:** Inconsistent .env files across servers lead to services connecting to wrong databases, using wrong API keys, or failing silently. The Wheeler ecosystem has multiple databases (frgops-standby, prediction-radar-app-db, aiops-ravynai-postgres, Hostinger-local PG) and it is easy for a DATABASE_URL to point to the wrong instance.
- **Impact:** High -- service partially functional or fully broken. Could affect multiple services if a shared env var (e.g., REDIS_URL) is wrong.
- **Likelihood:** High -- current .env management is entirely manual with no validation.
- **What could go wrong:** A service reads a stale DATABASE_URL and connects to the wrong database, writing data that appears to "disappear" from the correct database. A Stripe webhook secret is misconfigured, causing all payment webhooks to fail silently.
- **Current mitigation:** Manual review of env files during deploy. No automated validation.
- **Recommended mitigation:** 
  1. Create `.env.example` templates for each service
  2. Implement `preflight-check.sh` with env validation (required vars present, correct format, no duplicates)
  3. Add CI check for env file consistency between staging and production templates
  4. Document all env var locations in a single inventory
- **Effort to fix:** S (1-2 engineering-days)

#### Risk 3: Database Data Loss During Migration

- **Description:** A migration script drops a column or table still in use, or a failed migration leaves the database in an inconsistent state with no backup to restore. PostgreSQL DDL is transactional for most operations, but some (CREATE INDEX CONCURRENTLY, ALTER TYPE) are not, meaning a failed migration can leave partial changes.
- **Impact:** Critical -- data loss is the single most severe outcome in any system. Recovery may require restoring from a backup that is hours or days old, losing recent transactions.
- **Likelihood:** Medium -- migrations are infrequent but when they happen, they carry high risk. The lack of staging validation increases the probability of a bad migration reaching production.
- **What could go wrong:** A DROP COLUMN migration removes a column still referenced by application code. A data backfill migration updates rows incorrectly, corrupting business data. A migration runs against the wrong database because DATABASE_URL was incorrect.
- **Current mitigation:** None. No pre-migration backup process is automated or enforced.
- **Recommended mitigation:**
  1. Mandatory `pg_dump` before every migration (automated, not optional)
  2. Validate every migration on staging database with production-like data volume FIRST
  3. Require downgrade script for every migration (tested on staging)
  4. Implement migration safety checks (no DROP without confirmation, lock timeout, statement timeout)
  5. Keep backups for minimum 7 days post-migration
- **Effort to fix:** M (3-4 engineering-days)

#### Risk 4: Secret Exposure in Logs or Configs

- **Description:** API keys, database passwords, Stripe keys, or other secrets are accidentally committed to git, printed in PM2 logs, exposed in error messages, or visible in environment dumps. The Stripe test keys found in Prediction Radar's production environment demonstrate that secret hygiene is already a concern.
- **Impact:** Critical -- exposed secrets can lead to unauthorized API access, financial loss (Stripe key compromise), data breach, or service takeover.
- **Likelihood:** Medium -- secrets in .env files are gitignored but there is no scanning to verify this. PM2 logs may capture environment variables during crash dumps.
- **What could go wrong:** A developer accidentally commits a .env file. An error traceback includes an API key in the request URL. A deployment script echoes environment variables. The Stripe test keys are actually live keys accidentally labeled as test.
- **Current mitigation:** .gitignore for .env files. No secret scanning, no log redaction.
- **Recommended mitigation:**
  1. Implement secret scanning in CI (git-secrets, truffleHog, or GitHub secret scanning)
  2. Move secrets to a secrets manager (Doppler free tier to start)
  3. Add log redaction middleware (strip Authorization headers, mask key patterns)
  4. Audit all current .env files for hardcoded secrets that should be rotated
  5. Rotate the Stripe keys found in Prediction Radar (verify live vs test mode)
- **Effort to fix:** M (3-5 engineering-days)

#### Risk 5: Production Outage from PM2 Restart Loop

- **Description:** A bad deploy causes a PM2 service to crash immediately on start. PM2's auto-restart keeps restarting it, creating a restart loop that burns CPU and generates noise while the service remains down. The SurplusAI Scraper Agent and Voice Agent Service have already demonstrated this pattern with 282+ restart attempts each.
- **Impact:** High -- service unavailable. For the FRGCRM API (already errored with 15 restarts), this means CRM operations are offline.
- **Likelihood:** Medium -- the ecosystem already has services in restart loops (SurplusAI, Voice Agent). New deployments could trigger additional restart loops.
- **What could go wrong:** A deployment introduces an import error. PM2 restarts the process 10 times in 60 seconds, then stops (max_restarts). The service remains down until manually fixed. Meanwhile, dependent services (FRGCRM Agent Service depending on FRGCRM API) cascade into failure.
- **Current mitigation:** PM2 max_restarts configured (10 restarts in 60 seconds). After that, PM2 stops restarting. This prevents infinite CPU burn but does not restore the service.
- **Recommended mitigation:**
  1. Add health-check-gated deploy: do not switch traffic until new instance proves healthy
  2. Implement restart loop detection in monitoring (alert when restarts > 3 in 5 minutes)
  3. Auto-stop service after max_restarts exceeded AND notify on-call
  4. Test every deployment on a canary instance before promoting to production
- **Effort to fix:** S (1-2 engineering-days)

#### Risk 6: Cross-Server Config Drift

- **Description:** The same service or dependency configured differently on different servers (different env vars, different PM2 settings, different resource limits). With three servers and multiple databases, the opportunity for drift is high. For example, a service may point to Hostinger PG on EDGE but COREDB PG on AIOPS.
- **Impact:** Medium -- inconsistent behavior that is difficult to debug. May cause intermittent failures that only appear under specific routing conditions.
- **Likelihood:** High -- the ecosystem already has duplicate DATABASE_URL definitions and multiple PostgreSQL instances. Without standardization, drift is inevitable.
- **What could go wrong:** A deployment script works on AIOPS but fails on EDGE because a directory path is different. A health check passes on one server but fails on another because the expected port is different. Debugging takes hours because "it works on my machine" (or "it works on AIOPS").
- **Current mitigation:** None. No centralized config management. No config drift detection.
- **Recommended mitigation:**
  1. Standardize directory structures across all servers (`/opt/wheeler/services/`, `/opt/wheeler/env/`, `/opt/wheeler/backups/`)
  2. Create config templates with server-specific overrides in a single location
  3. Add config drift check to preflight-check.sh
  4. Version all configuration in git
- **Effort to fix:** S (1-2 engineering-days)

#### Risk 7: AI Model Routing Failure During Deploy

- **Description:** During deployment of AI workers or LiteLLM proxy, the model routing configuration breaks, causing all AI inference requests to fail. The Wheeler ecosystem depends on multiple AI providers (DeepSeek, OpenRouter, Anthropic, OpenAI) through LiteLLM, and a misconfiguration can take down all AI features simultaneously.
- **Impact:** High -- all AI-dependent features fail: Prediction Radar insights, RavynAI document analysis, Wheeler Brain agents, SurplusAI asset identification. This is a single point of failure for the entire AI layer.
- **Likelihood:** Low -- AI routing configuration changes infrequently. However, when it does change (API key rotation, model upgrade, provider switch), the blast radius is large.
- **What could go wrong:** LiteLLM config references a model name that no longer exists. An API key expires and the fallback path to OpenRouter is not configured. A new model version requires a different API endpoint that is not updated in the routing table.
- **Current mitigation:** Circuit breaker planned in LiteLLM config (cooldown, retry, fallback). OpenRouter is configured as a backup provider but the failover has not been tested end-to-end.
- **Recommended mitigation:**
  1. Test AI model routing validation before switching any traffic (part of preflight-check.sh for AI workers)
  2. Test OpenRouter fallback manually on a schedule (weekly)
  3. Implement health-check-gated AI deploy (verify inference works before promoting)
  4. Add model API status monitoring (DeepSeek status page, OpenRouter status page)
- **Effort to fix:** S (1-2 engineering-days)

---

## 4. Services: Deployability Assessment

### 4.1 Safe to Deploy Now

These services can be deployed today with minimal risk because they have clear rollback paths, low blast radius, or are inherently stateless.

| Service | Server | Why Safe | Watch Points |
|---------|--------|----------|--------------|
| **Frontend static apps (FRGCRM Frontend, Wheeler Hub, SurplusAI Portal)** | EDGE | Static files with atomic symlink swap. Nginx validates config. Visual verification is immediate. Rollback is a symlink change (seconds). | Clear CDN/browser cache after deploy. Verify API endpoints are reachable post-deploy from the frontend's perspective. |
| **Nginx configuration changes** | EDGE | `nginx -t` validates syntax before applying. Reload is instant and atomic. Previous config can be restored from backup in seconds. | Test all server blocks with curl before closing the SSH session. A bad config that passes syntax check but has wrong routing can still break services. |
| **Grafana / Uptime Kuma (monitoring tools)** | EDGE / AIOPS | Read-only dashboards. Stateless. Failures do not affect revenue services. Docker compose makes rollback straightforward. | Verify data sources are still reachable post-deploy. Uptime Kuma monitors should not alert during its own deployment. |
| **ChangeDetection (utility)** | AIOPS | Low criticality. No revenue impact if down briefly. Docker-based, easy restart. | Verify watch configurations are preserved across deploy. |
| **Spiderfoot (OSINT tool)** | AIOPS | Isolated service, no upstream dependencies. Low criticality. | Verify port binding on restart. |

### 4.2 Unsafe to Deploy

These services require specific fixes before they can be considered safe to deploy. Deploying them in their current state carries unacceptable risk.

| Service | Server | Why Unsafe | Required Fixes | Effort |
|---------|--------|------------|----------------|--------|
| **FRGCRM API** | AIOPS | Currently ERRORED (15 restart attempts). No rollback path. No health check gating. No pre-deploy backup. If deployed now and fails, recovery is entirely manual. | 1. Fix current errored state first. 2. Add health endpoint with dependency checks. 3. Test rollback on staging. 4. Implement pre-deploy backup. | M |
| **SurplusAI API** | AIOPS | No health endpoint verified. No rollback path tested. Depends on SurplusAI Scraper Agent (itself in restart loop). | 1. Verify/add health endpoint. 2. Test rollback. 3. Fix Scraper Agent dependency first. | M |
| **SurplusAI Scraper Agent** | AIOPS | WAITING status with 282+ restart attempts. Root cause unknown. Deploying on top of a broken process is high risk. | 1. Diagnose and fix root cause of restart loop. 2. Stabilize process. 3. Then add rollback and health checks. | M |
| **Voice Agent Service** | AIOPS | WAITING status with 282+ restart attempts. Same restart loop pattern as SurplusAI Scraper. | 1. Diagnose root cause. 2. May depend on FRGCRM API being fixed first. 3. Add health checks and rollback after stabilization. | M |
| **Prediction Radar API + Worker + Scheduler + Dashboard** | AIOPS | Most complex deployment (4 interconnected Docker containers). Stripe test keys in production env. If any container fails, revenue is directly impacted. | 1. Verify Stripe key mode (test vs live). 2. Test full docker compose rollback. 3. Validate health checks on all 4 containers. 4. Pre-deploy backup of Docker volumes. | L |
| **LiteLLM Proxy** | Hostinger EDGE | Single point of failure for ALL AI features. If routing config breaks during deploy, all AI services fail. Fallback to OpenRouter not tested. | 1. Test OpenRouter fallback end-to-end. 2. Add circuit breaker validation to preflight. 3. Verify model list matches worker expectations. | S |
| **Database migrations (any database)** | COREDB | No pre-migration backup enforced. No staging validation required. No downgrade testing. Data loss risk is unmitigated. | 1. Implement mandatory pre-migration pg_dump. 2. Require staging validation. 3. Test downgrade path for every migration. | M |
| **Traefik configuration** | EDGE | Routing changes affect ALL services. A bad config can take down the entire public ingress. No automated config validation step in deploy process. | 1. Add traefik config validation step before applying. 2. Backup current config before any change. 3. Test config rollback. | S |
| **Webhook Receiver** | Hostinger EDGE | Critical for Stripe payment processing. If down, payment webhooks are missed. Unknown health status. | 1. Verify service is running and healthy. 2. Add health endpoint. 3. Test webhook replay capability. | S |

---

## 5. Rollout Priorities (Phased Approach)

### Phase 1 -- Foundation: Safety Nets (Week 1-2)

**Goal:** Make it impossible to lose data or configuration during any operation.

**What this phase delivers:**
- Every server has working, tested backups (config, code, environment)
- Basic health check monitoring catches failures
- Environment files are standardized across all services
- Deployment audit log exists

**Key milestones:**

| # | Action | Server(s) | Success Criteria | Est. Effort |
|---|--------|-----------|-----------------|-------------|
| 1.1 | Deploy pre-deploy-backup.sh to all 3 servers | EDGE, AIOPS, COREDB | Script runs without errors; backup files exist and are non-empty | 1 day |
| 1.2 | Configure daily DB backup cron (pg_dumpall) | COREDB | Backup files exist, are compressed, and SHA256 checksums verified | 0.5 day |
| 1.3 | Set up backup retention policy (7 days config, 30 days DB) | All | Old backups are auto-cleaned; retention policy documented | 0.5 day |
| 1.4 | Deploy health check cron job (every 5 minutes) | EDGE, AIOPS | Health checks run on schedule; results logged; failures alerted | 1 day |
| 1.5 | Test backup restoration on staging | COREDB, AIOPS | Full restore from backup succeeds; application functions after restore | 1 day |
| 1.6 | Create /var/log/wheeler/ directory structure on all servers | All | All logs have a defined location; permissions correct | 0.5 day |
| 1.7 | Create deployment audit log mechanism | AIOPS | Every deployment is logged with timestamp, operator, version, status | 0.5 day |

**Phase 1 success criteria (all must be true):**
- [ ] Backups running on all 3 servers (verified by file existence + checksum)
- [ ] One successful test restore on staging
- [ ] Health checks running and alerting every 5 minutes
- [ ] Deployment audit log has at least one entry

---

### Phase 2 -- Safe Deployments (Week 3-4)

**Goal:** Every deployment is scripted, validated, and rollback-able.

**What this phase delivers:**
- Standardized deployment commands work for every service type
- Rollback is tested and timed for every service type
- Pre-deploy validation catches config errors before they reach production
- Post-deploy health checks confirm success before operator signs off

**Key milestones:**

| # | Action | Server(s) | Success Criteria | Est. Effort |
|---|--------|-----------|-----------------|-------------|
| 2.1 | Audit and standardize all .env files | All | All .env files follow naming convention; zero duplicates; all pass validation | 1 day |
| 2.2 | Implement preflight-check.sh validation | All | Preflight catches: missing env vars, port conflicts, disk space, SSL expiry, connectivity | 1 day |
| 2.3 | Build and test deploy-service.sh (all service types) | Staging | Successful deploy; health check passes; version verified | 2 days |
| 2.4 | Build and test rollback.sh (all service types) | Staging | Rollback restores service to healthy previous version; timed (< 2 min target) | 2 days |
| 2.5 | Implement post-deploy-healthcheck.sh | All | Health check report generated; JSON output; pass/fail decision | 0.5 day |
| 2.6 | Document playbooks (DEPLOYMENT_PLAYBOOKS.md) | N/A | All 8 playbooks written, reviewed, and validated on staging | 1 day |

**Phase 2 success criteria (all must be true):**
- [ ] Full deploy -> validate -> rollback cycle tested on staging for all service types (PM2, Docker, static)
- [ ] Rollback completes in under 2 minutes for all service types
- [ ] Zero env validation errors on preflight check across all servers
- [ ] All 8 playbooks validated on staging

---

### Phase 3 -- Advanced (Week 5-6)

**Goal:** CI/CD pipeline automates build, test, and deployment validation. Canary deployments are available for high-risk services.

**What this phase delivers:**
- Green CI builds on main branch
- Automated testing gate before deployment
- Canary deployment capability for one service (pilot)
- AI-specific deployment validation

**Key milestones:**

| # | Action | Server(s) | Success Criteria | Est. Effort |
|---|--------|-----------|-----------------|-------------|
| 3.1 | Enable build-validation.yml in GitHub Actions | CI | Build passes on main branch; failure blocks PR merge | 1 day |
| 3.2 | Enable lint.yml and tests.yml | CI | Linting passes; test suite runs; coverage reported | 1 day |
| 3.3 | Configure docker-build.yml for container services | CI | Docker images built and pushed to registry on merge to main | 1 day |
| 3.4 | Enable automated health check alerts | AIOPS | Health check failures trigger Slack notification within 2 minutes | 0.5 day |
| 3.5 | Configure Traefik weighted routing for canary pilot | EDGE | 5% traffic successfully routed to canary instance; monitoring confirms split | 1 day |
| 3.6 | Test canary deploy -> validate -> promote flow | Staging | Full canary cycle completes (5% -> 25% -> 50% -> 100%); metrics validated at each stage | 1 day |
| 3.7 | Implement AI deployment validation scripts | AIOPS | Model inference test runs pre and post deploy; circuit breaker state validated | 1 day |

**Phase 3 success criteria (all must be true):**
- [ ] Green CI build on main branch with all checks passing
- [ ] Canary deploy -> validate -> promote flow works end-to-end on staging
- [ ] AI deployment validation passes (inference test, streaming test, token usage check)

---

### Phase 4 -- Mature Operations (Week 7-8)

**Goal:** Zero-downtime deployments with full observability, automated rollback, and self-healing capabilities.

**What this phase delivers:**
- All eligible services support canary deployments
- Deployment dashboard provides real-time visibility
- Automated rollback triggers on health check failure
- Full disaster recovery test completed

**Key milestones:**

| # | Action | Server(s) | Success Criteria | Est. Effort |
|---|--------|-----------|-----------------|-------------|
| 4.1 | Roll out canary deployments to all eligible services | EDGE, AIOPS | Each service has documented canary config; traffic splitting tested | 2 days |
| 4.2 | Deploy deployment dashboard | EDGE | Dashboard shows real-time deploy status, health, rollback history for all services | 1 day |
| 4.3 | Implement automated rollback triggers | AIOPS | Health check failure for > 60s triggers automatic rollback; notification sent | 1 day |
| 4.4 | Add AI-specific deployment validation (circuit breaker, model routing, token budget) | AIOPS | AI workers validated pre and post deploy with model inference tests | 1 day |
| 4.5 | Full disaster recovery test | All | Simulate COREDB failure; restore from backup on new instance; all services recover | 2 days |
| 4.6 | Document all procedures and finalize release-validation.sh | All | Release validation passes on all 3 servers; all gaps documented | 1 day |

**Phase 4 success criteria (all must be true):**
- [ ] Canary deploy -> auto-validate -> auto-promote flow works end-to-end
- [ ] Deployment dashboard operational and accurate
- [ ] Automated rollback tested and verified
- [ ] DR test completes successfully (all services recoverable from backups)

---

## 6. 7-Day Release Engineering Roadmap

### Day 1 -- Backup & Monitor Foundation

**Theme:** Make it impossible to lose data or configuration.

| # | Task | Owner | Priority | Success Criteria |
|---|------|-------|----------|-----------------|
| D1.1 | Deploy pre-deploy-backup.sh to all 3 servers | Release Eng | P0 | Script runs successfully on each server; backup files verified non-empty |
| D1.2 | Configure daily DB backup cron: `pg_dumpall` all databases on COREDB | Release Eng | P0 | Cron job active; backup files exist; checksums verified |
| D1.3 | Set up backup retention policy: 7 days config, 30 days DB | Release Eng | P1 | Old backups auto-cleaned via cron; retention documented |
| D1.4 | Deploy health check cron (every 5 min) checking all service endpoints | Release Eng | P0 | Health check script runs; results logged to `/var/log/wheeler/health/` |
| D1.5 | Test backup restoration on one server (staging or COREDB test database) | Release Eng | P0 | `pg_restore` succeeds; application queries work after restore |
| D1.6 | Create `/var/log/wheeler/` directory structure on all servers | Release Eng | P1 | All deploy/rollback/backup/health logs have a defined home |
| D1.7 | Set up Slack webhook for health check alerting | Release Eng | P1 | Consecutive health check failures (> 2) trigger Slack notification to #deployments |

**Day 1 Success Criteria:**
- [ ] Backups working on all 3 servers (verified by file existence and non-zero size)
- [ ] One successful test restore on staging or COREDB test database
- [ ] Health checks running every 5 minutes
- [ ] Health check alerting configured (Slack notification on failure)

---

### Day 2 -- Environment Standardization

**Theme:** Eliminate config drift and ensure all .env files are valid and consistent.

| # | Task | Owner | Priority | Success Criteria |
|---|------|-------|----------|-----------------|
| D2.1 | Audit all current .env files across all 3 servers (full inventory) | Release Eng | P0 | Complete inventory: every .env file location, purpose, and variables documented |
| D2.2 | Create standardized .env.{service}.{environment} naming for each service | Release Eng | P0 | All services have standardized env file paths: `/opt/wheeler/env/<service>/<env>/.env` |
| D2.3 | Create .env.example template for each service from the audit | Release Eng | P0 | Template documents every required variable with type, default, and description |
| D2.4 | Migrate all env files to standardized naming; remove duplicate DATABASE_URL definitions | Release Eng | P0 | Zero duplicate variable definitions; each variable defined exactly once per environment |
| D2.5 | Run preflight-check.sh against all env files; fix all validation errors | Release Eng | P0 | All env files pass validation (no missing required vars, no syntax errors) |
| D2.6 | Scan all env files for hardcoded secrets that should be rotated | Release Eng | P1 | List of secrets requiring rotation (especially Stripe sk_test_* in Prediction Radar) |
| D2.7 | Document env file locations and purpose in environment inventory | Release Eng | P1 | Single source of truth for all environment configuration |

**Day 2 Success Criteria:**
- [ ] All .env files follow standardized naming: `/opt/wheeler/env/<service>/<env>/.env`
- [ ] Zero environmental validation errors from preflight-check.sh
- [ ] Zero duplicate variable definitions (e.g., DATABASE_URL defined in only one place)
- [ ] Complete env file inventory documented
- [ ] Stripe key mode verified (test vs live) for Prediction Radar

---

### Day 3 -- Deployment Scripts

**Theme:** Every deployment is scripted and validated -- no more ad-hoc SSH commands.

| # | Task | Owner | Priority | Success Criteria |
|---|------|-------|----------|-----------------|
| D3.1 | Test deploy-service.sh on staging for static frontend (FRGCRM Frontend) | Release Eng | P0 | Successful deploy: build artifact pulled, extracted, symlink updated, Nginx reloaded, health check passes |
| D3.2 | Test deploy-pm2-service.sh on staging for PM2 service (FRGCRM API) | Release Eng | P0 | Successful deploy: code pulled, deps installed, PM2 reloaded, process online, health check passes |
| D3.3 | Test deploy-docker-service.sh on staging for Docker service (RavynAI API) | Release Eng | P0 | Successful deploy: image pulled, container restarted, healthy, no downtime |
| D3.4 | Test deploy-pm2-service.sh on staging for AI worker (FRGCRM Agent Service) | Release Eng | P0 | Successful deploy: PM2 reloaded, inference test passes, token usage normal |
| D3.5 | Validate all health checks pass post-deploy (JSON response, version match, dependency checks) | Release Eng | P1 | All health endpoints return 200 with expected JSON structure |
| D3.6 | Document deploy commands per service type in quick reference | Release Eng | P1 | One-page quick reference showing exact deploy command for each service type |
| D3.7 | Run deploy-log.sh record for each test deploy | Release Eng | P1 | Deployment audit log populated with test deploy entries |

**Day 3 Success Criteria:**
- [ ] All four deploy scripts tested on staging (static, PM2, Docker, AI worker)
- [ ] All health checks pass post-deploy
- [ ] Deployment audit log has entries for all test deploys
- [ ] Each service type has a documented deploy command

---

### Day 4 -- Rollback Engine Testing

**Theme:** Rollback must work every time, for every service type, faster than deployment.

| # | Task | Owner | Priority | Success Criteria |
|---|------|-------|----------|-----------------|
| D4.1 | Test /root/rollback-engine/rollback.sh for PM2 services | Release Eng | P0 | Deploy v2, simulate failure, rollback to v1, verify v1 is healthy, timed |
| D4.2 | Test rollback.sh for Docker services | Release Eng | P0 | Container restored to previous image, volumes intact, health check passes |
| D4.3 | Test rollback.sh for static frontends (symlink swap) | Release Eng | P0 | Previous build restored, Nginx reloaded, public URL returns 200 |
| D4.4 | Test restore-env.sh: restore .env from backup and verify service health | Release Eng | P0 | Env file restored, diff shows expected changes only, service health unaffected |
| D4.5 | Test restore-routing.sh: restore Traefik/Nginx config from backup | Release Eng | P0 | Routing configs restored, all routes working, public URLs accessible |
| D4.6 | Time all rollback operations; document results | Release Eng | P1 | PM2 rollback: < 30s. Docker rollback: < 60s. Static rollback: < 15s. Full DB restore: < 5 min. |
| D4.7 | Test emergency rollback scenario: simulate production failure, execute full rollback under time pressure | Release Eng | P1 | Team practices rollback; identifies friction points; procedure refined |

**Day 4 Success Criteria:**
- [ ] Rollback tested and timed for all service types (PM2, Docker, static, DB)
- [ ] All rollbacks complete in under 2 minutes (PM2/Docker/static) or under 5 minutes (DB)
- [ ] Rollback timing documented in playbooks
- [ ] Emergency rollback drill completed; friction points identified and resolved

---

### Day 5 -- CI/CD Pipeline Setup

**Theme:** Automated build, test, and validation in CI. No manual test runs before deploy.

| # | Task | Owner | Priority | Success Criteria |
|---|------|-------|----------|-----------------|
| D5.1 | Enable build-validation.yml in GitHub Actions | Release Eng | P0 | Build passes on main branch; build failure blocks PR merge |
| D5.2 | Enable lint.yml (ESLint for JS, Black+Ruff for Python, ShellCheck for bash) | Release Eng | P0 | Linting passes on main; lint errors block PR merge |
| D5.3 | Enable tests.yml (Jest for JS, Pytest for Python) | Release Eng | P0 | All test suites pass on main; test failures block PR merge |
| D5.4 | Test docker-build.yml with a sample service (RavynAI API or Docuseal) | Release Eng | P1 | Image built in CI, pushed to registry, pullable on staging |
| D5.5 | Enable deployment-validation.yml (runs preflight checks, validates env files) | Release Eng | P1 | CI catches config errors before they reach a human operator |
| D5.6 | Configure branch protection rules on main | Release Eng | P1 | PR requires: CI pass, 1 approval, no unresolved conversations |
| D5.7 | Enable health-check.yml (scheduled workflow, runs every 5 min against all servers) | Release Eng | P1 | Health check runs on schedule; failures create GitHub Issue |

**Day 5 Success Criteria:**
- [ ] All CI workflows green on main branch
- [ ] Branch protection enabled (CI pass required before merge)
- [ ] Docker image build and push working in CI for at least one service
- [ ] Scheduled health check runs and reports status

---

### Day 6 -- Canary & AI Validation

**Theme:** Gradual traffic shifting and AI-specific validation tested end-to-end.

| # | Task | Owner | Priority | Success Criteria |
|---|------|-------|----------|-----------------|
| D6.1 | Configure Traefik weighted routing for canary test on one service | Release Eng | P0 | Traefik config validated; 5% traffic routed to canary instance |
| D6.2 | Deploy canary instance of one service (PM2 or Docker) | Release Eng | P0 | Canary instance healthy on separate port; monitoring confirms |
| D6.3 | Test gradual traffic increase: 5% -> 25% -> 50% | Release Eng | P0 | Traffic shift works at each stage; metrics dashboard shows split correctly |
| D6.4 | Test canary promotion to 100% and canary abort (rollback to 0%) | Release Eng | P0 | Both promote and abort flows work; service healthy after both |
| D6.5 | Test AI deployment validation: model inference test pre and post deploy | Release Eng | P1 | Inference test (DeepSeek, OpenRouter) passes after worker deploy |
| D6.6 | Test circuit breaker failover: DeepSeek -> OpenRouter | Release Eng | P1 | Simulate DeepSeek failure; requests automatically route to OpenRouter; circuit breaker logs confirm |
| D6.7 | Test streaming response validation for AI workers | Release Eng | P1 | SSE streaming works post-deploy; no buffering issues from proxy |

**Day 6 Success Criteria:**
- [ ] Canary deploy -> validate -> promote flow works end-to-end for one service
- [ ] Canary abort (rollback to 0%) tested and verified
- [ ] AI inference validation works pre and post deploy
- [ ] Circuit breaker failover (DeepSeek -> OpenRouter) tested
- [ ] Streaming responses validated

---

### Day 7 -- Full System Integration

**Theme:** End-to-end validation across all servers and services. Document gaps.

| # | Task | Owner | Priority | Success Criteria |
|---|------|-------|----------|-----------------|
| D7.1 | Run full deploy -> validate -> rollback cycle on staging for all service types | Release Eng | P0 | Complete cycle passes for static, PM2, Docker, and AI worker |
| D7.2 | Run release-validation.sh against all 3 servers | Release Eng | P0 | All checks pass OR issues documented with owner and deadline |
| D7.3 | Run deployment playbook walkthrough: team executes Playbooks 1-8 on staging | Release Eng | P0 | Team can execute each playbook independently; gaps documented |
| D7.4 | Test emergency rollback scenario on staging: deploy bad version, detect failure, rollback | All Operators | P0 | Time from failure detection to healthy service under 5 minutes |
| D7.5 | Document all gaps found during integration testing | Release Eng | P1 | Gap list with: description, severity, owner, estimated effort, deadline |
| D7.6 | Create final state report: week's achievements, remaining gaps, next steps | Release Eng | P1 | Executive summary ready for CTO/VP Engineering review |
| D7.7 | Team retrospective: what went well, what didn't, what to change for next iteration | All | P1 | Feedback incorporated into roadmap; process improvements documented |

**Day 7 Success Criteria:**
- [ ] Release validation passes on all 3 servers
- [ ] Team can execute all 8 playbooks independently
- [ ] Emergency rollback drill completed (under 5 minutes from detection to healthy)
- [ ] Gap list documented with owners and deadlines
- [ ] Final state report delivered
- [ ] Team retro completed

---

## 7. Investment & Resource Needs

### 7.1 Tools and Services Needed

| Need | Recommendation | Cost Estimate | Priority | Notes |
|------|---------------|---------------|----------|-------|
| **CI/CD Platform** | GitHub Actions (included with GitHub) | $0 (public repos); usage-based for private | P0 | Wheeler repos on GitHub; Actions minutes included in plan |
| **Secrets Manager** | Doppler (free tier: 5 users, unlimited projects) | $0 to start; $5/seat/month beyond 5 | P0 | Start with free tier; migrate from .env files incrementally |
| **Container Registry** | GitHub Container Registry (ghcr.io) | $0 (included with GitHub) | P0 | Already available; just needs workflow configuration |
| **Monitoring Dashboard** | Grafana (self-hosted on AIOPS, already deployed) | $0 | P1 | Add deployment-specific dashboards to existing Grafana instance |
| **Log Aggregation** | Loki + Promtail (already on monitoring stack) | $0 | P1 | Configure deployment-specific log queries and alerts |
| **Alerting** | Slack webhook (free) + existing notification channels | $0 | P1 | #deployments and #incidents channels exist |
| **Uptime Monitoring** | Uptime Kuma (already deployed on EDGE/AIOPS) | $0 | P2 | Add deployment-specific monitors to suppress during maintenance windows |
| **Status Page** | Self-hosted or statuspage.io free tier | $0 | P3 | Not needed for Phase 1-2; consider for Phase 4 |

### 7.2 Skills Gaps in the Team

| Skill | Current State | Needed For | Gap Severity | Mitigation |
|------|-------------|------------|-------------|------------|
| **Bash scripting** | Strong (deployment scripts exist) | Deployment scripts, backup scripts, health checks | None | Existing team capability |
| **Docker** | Strong (24 services containerized) | Docker compose deploys, container rollback | None | Existing team capability |
| **PM2** | Strong (production PM2 management) | PM2 service deploys, ecosystem management | None | Existing team capability |
| **GitHub Actions** | Moderate | CI/CD pipeline authoring, workflow design | Minor | YAML syntax and workflow design are learnable in 1-2 days. GitHub Actions documentation is excellent. |
| **Traefik** | Moderate | Canary weighted routing, health check middleware, circuit breakers | Minor | Weighted routing and health checks are well-documented. Canary config templates exist. |
| **PostgreSQL backup/restore** | Moderate | pg_dump/pg_restore best practices, PITR, backup verification | Minor | pg_dump usage is straightforward. Point-in-time recovery is Phase 3+. |
| **Secret management** | Basic | Doppler integration, secret rotation, log redaction | Moderate | New tool adoption. Doppler has good docs. Rotation workflow needs design. |
| **Observability (Prometheus/Grafana/Loki)** | Basic-to-Moderate | Deployment-specific dashboards, alert rules, anomaly detection | Moderate | Grafana dashboard design is learnable. Alert rules need careful tuning. |

### 7.3 Time Commitment Estimate per Phase

| Phase | Calendar Time | Focus Time (1 dedicated person) | Parallelizable? | Notes |
|-------|--------------|-------------------------------|-----------------|-------|
| Phase 1: Foundation | 1 week | 4-5 days | High -- backups and monitoring are independent tasks | Most tasks are script deployment and cron configuration |
| Phase 2: Safe Deployments | 1-2 weeks | 5-7 days | Medium -- env standardization can parallel script development | Script testing requires sequential staging validation |
| Phase 3: Advanced | 1-2 weeks | 5-7 days | High -- CI workflows built in parallel; canary config is independent | CI workflows for different languages are independent |
| Phase 4: Mature Operations | 2-3 weeks | 8-10 days | Medium -- dashboard, canary rollout, DR test can parallelize partially | DR test requires all services to be deployable first |

**Total estimated focus time:** 22-29 person-days over 5-8 calendar weeks for one dedicated Release Engineer.

**With 2 engineers:** 11-15 person-days per engineer over 3-5 calendar weeks.
**With part-time allocation (50%):** Double the calendar time estimates.

### 7.4 External Dependencies and Blockers

| Dependency | Impact if Not Available | Mitigation |
|------------|------------------------|------------|
| **SSH access to all 3 servers** | Cannot deploy scripts or run validation | Ensure Tailscale connectivity is stable. Document out-of-band access methods (Hostinger panel, Hetzner console). |
| **GitHub repository admin access** | Cannot configure branch protection or enable required CI checks | Request admin access from repo owner before Day 5. |
| **Doppler account (or alternative secrets manager)** | Secrets remain in plaintext .env files | Can proceed with Phase 1-2 without secrets manager. Phase 3+ benefits from it but is not blocked. |
| **Stripe API admin access** | Cannot verify or rotate Stripe keys for Prediction Radar | Request access from billing/ops team before Day 2. This is a critical revenue issue. |
| **DNS management access (Cloudflare)** | Cannot verify or update DNS records if needed | Should not be needed for deployment improvements. Only needed for cutover scenarios. |
| **Team availability for playbook walkthrough** | Playbooks not validated by real operators | Schedule walkthrough well in advance. Record walkthrough for async review if needed. |

---

## 8. Critical Success Factors

### 8.1 What Must Go Right

1. **Backups must be reliable and tested.** A backup that has never been restored is not a backup -- it is a hope. Restoration must be tested within the first 48 hours. The backup verification step (checksum comparison) is non-negotiable. The most common backup failure mode is silent corruption; without checksums, you do not know the backup is good until you need it.

2. **Rollback must work every time, for every service type.** The rollback path is more important than the deploy path. If a deploy fails and rollback also fails, the operator is stuck with a broken production service and no recovery path. Rollback must be tested weekly on staging. Every new service type added to the ecosystem must have a tested rollback before its first production deploy.

3. **Health checks must catch real failures quickly.** A health check that returns 200 when the service is actually broken creates a false sense of safety. Health checks must validate: (a) the process is running, (b) dependencies are reachable (database, Redis, model APIs), (c) the application can perform a basic operation (query a known row, run a test inference). Validate health checks by intentionally breaking services on staging and confirming the health check fails.

4. **The team must follow playbooks, not ad-hoc deploy habits.** The best deployment scripts are worthless if the team habitually SSH's in and runs `git pull && pm2 restart`. This is a culture change, not a tooling change. The playbook walkthrough (Day 7) is as much about habit formation as it is about validation. Lead by example: every operator, including senior engineers, must use the playbooks.

5. **Staging must mirror production.** A deployment that works perfectly on staging but fails on production means staging is not fit for purpose. Staging and production must have: (a) the same operating system and package versions, (b) the same database schema (via regular sync or migration), (c) the same PM2/Docker configurations (minus scale), (d) representative data volume. The most common cause of staging/production parity failure is data: staging has 100 rows, production has 10 million, and the migration takes 3 seconds on staging and 30 minutes on production.

### 8.2 What Must Not Go Wrong

1. **No data loss during any deployment or rollback.** This is the one unforgivable outcome. Every deployment must begin with a verified backup. Every database migration must be reversible (or have a restore path). Every rollback must preserve user data written during the failed deployment window. If there is any question about data safety, stop the deployment and escalate.

2. **No production downtime caused by the deployment system itself.** The deployment scripts, health check cron jobs, and monitoring infrastructure must not be the thing that breaks production. Deployment scripts must be idempotent (safe to run multiple times). Health checks must be read-only. Monitoring must not consume resources that compete with production services. The deployment system must fail safely: if a deployment script encounters an error it cannot handle, it must stop and alert, not continue with partial state.

3. **No secret exposure in logs, configs, or error messages.** Secrets committed to git are forever (even if you force-push, they exist in clone histories and cache). Secrets printed in logs are captured by Loki and become searchable. Secrets in error messages are returned to clients. Implement secret scanning in CI before enabling verbose deployment logging. Add log redaction middleware that strips known secret patterns (API key prefixes, JWT tokens, Authorization headers).

4. **No orphaned processes or containers after deploy or rollback.** Old instances must be fully stopped and cleaned up. Orphaned processes consume memory and CPU. Orphaned containers hold port mappings that cause conflicts on the next deploy. Orphaned PM2 processes show as "online" in `pm2 list` but do not actually serve traffic, creating confusion during incident response. Every deploy script must verify that old instances are stopped before starting new ones. Every rollback script must clean up the failed version's processes.

5. **No deployment during unplanned hours without a rollback partner.** Solo deploys at 2 AM are how incidents become outages. Production deployments must have at least two people: one executing, one monitoring. If a deployment must happen outside the normal window (Tuesday-Thursday, 10:00-14:00 UTC), it requires explicit SRE Lead approval and a documented rollback partner. The rollback partner does not need to be actively involved -- they just need to be reachable within 5 minutes.

---

## 9. Appendices

### Appendix A: Server Connection Details (Reference Only)

| Server | Role | Provider | Public IP | Tailscale IP | SSH User | Access Method |
|--------|------|----------|-----------|-------------|----------|--------------|
| **EDGE** | Public ingress, static hosting, Traefik, Nginx, frontends | Hostinger | 187.77.148.88 | 100.110.48.189 | deployer | SSH via Tailscale (preferred) or direct IP + key |
| **AIOPS** | Application compute, PM2, AI workloads, Docker containers | Hetzner | 5.78.140.118 | 100.121.230.28 | deployer | SSH via Tailscale (preferred) or direct IP + key |
| **COREDB** | PostgreSQL 16, Redis 7, MinIO, pgvector, backups | Hetzner | 5.78.210.123 | 100.118.166.117 | deployer | SSH via Tailscale (preferred) or direct IP + key |

**Connectivity requirements:**
- EDGE -> AIOPS: WireGuard/Tailscale tunnel for internal API routing (Traefik backend -> PM2/Docker services)
- AIOPS -> COREDB: Direct network (same Hetzner region) for database and Redis connections
- EDGE -> COREDB: Tailscale tunnel for monitoring and backup copy operations
- Operator -> All servers: Tailscale or SSH key-based access

### Appendix B: Service Inventory

| # | Service | Node | Runtime | Port | Health Endpoint | Deploy Method | Revenue Impact |
|---|---------|------|---------|------|-----------------|---------------|----------------|
| 1 | Traefik Reverse Proxy | EDGE | Docker | 80, 443 | :8080/ping | docker-compose up -d | CRITICAL (all public ingress) |
| 2 | Nginx | EDGE | Docker | 8080 | /nginx-health | docker-compose up -d | HIGH (static assets, cache) |
| 3 | FRGCRM Frontend | EDGE | Docker/Next.js | 3000 | /health (assumed) | docker-compose up -d | CRITICAL (CRM, lead intake) |
| 4 | Wheeler Hub Dashboard | EDGE | Static/Next.js | 3000 | /health (assumed) | deploy-service.sh | MEDIUM (internal ops) |
| 5 | SurplusAI Frontend | EDGE | Static/Next.js | 3000 | /health (assumed) | deploy-service.sh | MEDIUM (external portal) |
| 6 | Chatwoot | EDGE | Docker | 3000 | /health (assumed) | docker-compose up -d | MEDIUM (customer messaging) |
| 7 | n8n Workflows | EDGE | Docker | 5678 | /health (assumed) | docker-compose up -d | MEDIUM (automation) |
| 8 | LiteLLM Proxy | EDGE | Docker | 4000 | /health | docker-compose up -d | CRITICAL (all AI routing) |
| 9 | Webhook Receiver | EDGE | Docker | 9000 | /health (assumed) | docker-compose up -d | HIGH (Stripe webhooks) |
| 10 | MinIO Console | EDGE | Docker | 9001 | /minio/health/live | docker-compose up -d | MEDIUM (object storage admin) |
| 11 | FRGCRM API | AIOPS | PM2 (fork) | varies | N/A (errored) | deploy-pm2-service.sh | CRITICAL (CRM operations) |
| 12 | SurplusAI API | AIOPS | PM2/Docker | varies | /health (assumed) | deploy-pm2-service.sh | HIGH (data pipeline) |
| 13 | FRGCRM Agent Service | AIOPS | PM2 (fork) | 8013 (IPv6) | /health | deploy-pm2-service.sh | HIGH (CRM automation) |
| 14 | FRGCRM Mirror Test | AIOPS | PM2 (fork) | 8003 (IPv6) | /health | deploy-pm2-service.sh | LOW (testing) |
| 15 | SurplusAI Scraper Agent | AIOPS | PM2 (fork) | N/A | N/A (waiting, 282 restarts) | deploy-pm2-service.sh | HIGH (data pipeline) |
| 16 | Voice Agent Service | AIOPS | PM2 (fork) | N/A | N/A (waiting, 282 restarts) | deploy-pm2-service.sh | HIGH (voice outreach) |
| 17 | Insforge Agent Service | AIOPS | PM2 (fork) | 8013 (IPv6) | /health (assumed) | deploy-pm2-service.sh | MEDIUM (agent logic) |
| 18 | RavynAI API | AIOPS | Docker | 8007 | /health | docker-compose up -d | HIGH (document analysis) |
| 19 | Prediction Radar API | AIOPS | Docker | 8000/8098 | /health | docker-compose up -d | CRITICAL (revenue SaaS) |
| 20 | Prediction Radar Worker | AIOPS | Docker | N/A | Internal | docker-compose up -d | CRITICAL (background jobs) |
| 21 | Prediction Radar Scheduler | AIOPS | Docker | N/A | Internal | docker-compose up -d | CRITICAL (scheduled tasks) |
| 22 | Prediction Radar Dashboard v2 | AIOPS | Docker | 3000 | Internal | docker-compose up -d | HIGH (SaaS dashboard) |
| 23 | Docuseal | AIOPS | Docker | 3010 | /health | docker-compose up -d | LOW (document signing) |
| 24 | OpenClaw AI Orchestrator | AIOPS | Docker | varies | /health (assumed) | docker-compose up -d | HIGH (AI orchestration) |
| 25 | Langflow | AIOPS | Docker | 7860 | /health | docker-compose up -d | MEDIUM (AI workflow builder) |
| 26 | Grafana | AIOPS | Docker | 3002 | /api/health | docker-compose up -d | LOW (monitoring) |
| 27 | Uptime Kuma | AIOPS | Docker | 3001 | / (HTTP 200) | docker-compose up -d | LOW (monitoring) |
| 28 | Superset | AIOPS | Docker | 8088 | /health | docker-compose up -d | LOW (analytics) |
| 29 | ChangeDetection | AIOPS | Docker | 5000 | /api/healthcheck | docker-compose up -d | LOW (utility) |
| 30 | Spiderfoot | AIOPS | Docker | 8080 | / (HTTP 200) | docker-compose up -d | LOW (OSINT) |
| 31 | PostgreSQL 16 | COREDB | Docker | 5432 | pg_isready | docker-compose (DB-safe) | CRITICAL (all data) |
| 32 | Redis 7 | COREDB | Docker | 6379 | redis-cli PING | docker-compose (DB-safe) | HIGH (caching, queues) |
| 33 | MinIO Object Storage | COREDB | Docker | 9000 | /minio/health/live | docker-compose (DB-safe) | MEDIUM (file storage) |
| 34 | pgvector | COREDB | Extension | N/A | SQL query | Alembic migration | MEDIUM (AI embeddings) |

### Appendix C: Key Contacts / Escalation Path

| Severity | Response Time | First Escalation | Second Escalation | Communication Channel |
|----------|--------------|-----------------|-------------------|----------------------|
| **Critical (P0)** -- Production down, revenue stopped, data loss | Immediate (< 5 min) | SRE Lead -> CTO | All engineers | Phone + Slack #incidents |
| **High (P1)** -- Major feature broken, significant degradation | < 15 minutes | Engineering Lead | SRE Lead | Slack #incidents |
| **Medium (P2)** -- Minor feature degraded, non-blocking issue | < 2 hours | Service Owner | Engineering Lead | Slack #engineering |
| **Low (P3)** -- Cosmetic issue, internal tool affected | Next business day | Ticket | N/A | GitHub Issues |

**Escalation contact list (to be filled by team):**

| Role | Name | Slack | Phone | Notes |
|------|------|-------|-------|-------|
| SRE Lead | [FILL] | @sre-lead | [FILL] | Primary on-call for deployment incidents |
| Engineering Manager | [FILL] | @eng-mgr | [FILL] | Approves hotfix deploys and migration windows |
| Release Engineer | [FILL] | @release-eng | [FILL] | Owns playbooks and deployment scripts |
| DBA / Data Engineer | [FILL] | @dba | [FILL] | Required for database migrations |
| CTO / VP Engineering | [FILL] | @cto | [FILL] | Escalation for critical revenue-impacting incidents |

### Appendix D: Glossary of Terms

| Term | Definition |
|------|------------|
| **Alembic** | Database migration tool for SQLAlchemy/Python. Tracks schema versions and applies incremental changes. |
| **Atomic Swap** | Changing a symlink to point to a new directory -- a single, instantaneous operation that cannot be interrupted midway. Used for zero-downtime static frontend deploys. |
| **Blue-Green Deployment** | Two identical environments (blue=current, green=new). Deploy to inactive environment, switch all traffic when ready. |
| **Canary Deployment** | Gradually shift a percentage of production traffic to the new version, monitoring for issues at each stage before increasing. |
| **Circuit Breaker** | Pattern that automatically stops calling a failing service after a threshold of errors, preventing cascading failures. Used in AI workers for model API failover (DeepSeek -> OpenRouter). |
| **COREDB** | The database/storage node (Hetzner, 5.78.210.123) hosting PostgreSQL 16, Redis 7, MinIO, and pgvector. |
| **EDGE** | The public ingress node (Hostinger, 187.77.148.88) hosting Traefik, Nginx, and frontend applications. |
| **AIOPS** | The application compute node (Hetzner, 5.78.140.118) hosting PM2-managed APIs, AI workers, and Docker containers. |
| **Graceful Shutdown** | Allowing in-flight requests to complete before stopping a process. PM2 sends SIGINT, waits for the process to exit, then sends SIGKILL if it hasn't exited after a timeout. |
| **Health Check** | An endpoint or command that verifies a service is functioning correctly. Must check more than "process is running" -- it must verify dependencies and basic operations work. |
| **Idempotent** | Safe to run multiple times. Running an idempotent deploy script twice produces the same result as running it once. Critical for safety. |
| **Immutable Deployment** | New version replaces old version entirely. No in-place updates. Docker containers and static frontend symlink swaps are immutable. |
| **LiteLLM** | AI model proxy that provides a unified OpenAI-compatible API for multiple model providers (DeepSeek, OpenAI, Anthropic, OpenRouter). |
| **Maintenance Mode** | State where a service returns a friendly "under maintenance" page instead of normal responses. Used during blocking database migrations. |
| **pg_dump / pg_dumpall** | PostgreSQL backup utilities. pg_dump backs up a single database. pg_dumpall backs up all databases and global objects (roles, tablespaces). |
| **PM2** | Node.js process manager used on AIOPS for API and worker services. Provides clustering, log management, auto-restart, and zero-downtime reloads. |
| **Preflight Check** | Validation script run before every deployment. Checks env vars, disk space, connectivity, SSL certs, and port availability. Deployment is blocked if preflight fails. |
| **Restart Loop** | A service crashes immediately on start. PM2 auto-restarts it. It crashes again. This repeats until max_restarts is exceeded. SurplusAI Scraper and Voice Agent are currently in this state (282+ restarts). |
| **Rollback** | Restoring the previous version of a service after a failed deployment. Must be faster than the deployment itself. |
| **Smoke Test** | A quick set of basic tests that verify the most critical functionality is working after a deploy (homepage loads, API returns 200, login page renders). |
| **Traefik** | Cloud-native reverse proxy and load balancer running on EDGE. Handles SSL termination, routing, rate limiting, and canary traffic splitting. |
| **Zero-Downtime Deployment** | Users experience no interruption during deployment. Achieved through PM2 rolling reload, Docker container replacement with health-check-gated traffic switching, or atomic symlink swaps for static files. |

---

**End of Document**

Document version: 2.0.0 | Last reviewed: 2026-05-23 | Next review: 2026-06-23

This document is maintained by Platform Engineering / Release Engineering. Submit changes via PR to `wheeler-org/platform-docs`. This report should be reviewed and updated monthly, or after any significant incident or infrastructure change.
