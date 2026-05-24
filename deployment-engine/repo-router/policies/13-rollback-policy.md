# PHASE-13: Rollback Policy

## Policy Name
Production Deployment Rollback Procedures and Triggers Policy

## Purpose
Define the mandatory rollback procedures, automatic triggers, and post-rollback actions for all production deployments executed through the Repo Router pipeline. Every deployment must have a tested, documented rollback plan.

## Scope
Applies to all production deployments across every Wheeler node: AI Ops, Hostinger, and Core-DB. Covers Docker Compose, PM2, nginx, and database migration rollbacks.

## Rules

### R1: Rollback Plan Requirement
1.1 Every repo MUST have a ROLLBACK.md file in its repository root before PHASE-13 deployment.
1.2 The rollback plan MUST cover: service rollback, database migration rollback, DNS changes, and config restoration.
1.3 The rollback plan MUST be tested in staging (PHASE-11/PHASE-12) before production use.

### R2: Automatic Rollback Triggers
2.1 The pipeline SHALL automatically trigger a rollback if any of the following occur within 30 minutes of deployment:
    2.1.1 Error rate increases by more than 5 percentage points above pre-deployment baseline.
    2.1.2 p99 latency increases by more than 2x the pre-deployment baseline.
    2.1.3 Service health check fails three consecutive times.
    2.1.4 Any critical alert fires for the deployed service.
    2.1.5 Deployment fails to complete within the configured timeout.

### R3: Rollback Execution
3.1 Docker Compose rollback: `docker compose -f docker-compose.yml up -d --no-deps <previous-image-tag>`
3.2 PM2 rollback: `pm2 delete <service> && pm2 start ecosystem.config.js --env production --only <previous-version>`
3.3 Database rollback: Execute the down-migration script for the specific release.
3.4 nginx rollback: Restore previous config from `/nginx/backups/` and reload.

### R4: Post-Rollback Actions
4.1 An incident MUST be opened for every automatic rollback.
4.2 The root cause MUST be documented within 24 hours.
4.3 The service MUST remain in staging until the root cause is resolved.
4.4 The deployment attempt MUST be tagged in Git with `deploy-fail-<timestamp>`.

### R5: Rollback Testing
5.1 Rollback procedures MUST be tested at least once per quarter for every production service.
5.2 Rollback testing results are documented and reviewed by operations.

## Enforcement Mechanism
Rollback plans are verified during PHASE-12 (Production Readiness). Automatic rollback triggers are monitored by the observability stack and executed by the Repo Router engine or a deployment orchestration tool. Rollback testing is tracked in a quarterly compliance report.

## Exception Process
Services without a tested rollback plan cannot deploy to production. No exceptions.

## Audit Trail Requirements
Every rollback execution is logged with trigger reason, duration, and outcome. Rollback test results are stored per quarter. Incident IDs are linked to rollback events for traceability.
