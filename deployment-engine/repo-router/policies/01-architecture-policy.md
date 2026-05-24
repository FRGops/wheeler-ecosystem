# PHASE-01: Architecture Standards Policy

## Policy Name
Repository Architecture and Standards Policy

## Purpose
Define mandatory architectural standards all repos must satisfy before entering the Wheeler Repo Router pipeline. Governs the Intake and Classification phase (PHASE-01).

## Scope
Applies to ALL repos submitted to the Repo Router pipeline:
- AI Ops Node repos: frgcrm, wheeler-revenue-automation, openclaw-dashboard, wheeler-ecosystem
- Hostinger Node repos: fundsrecoverygroup, frgops-surplusai, private-ai
- Core-DB infrastructure repos
- Third-party or candidate repos proposed for deployment

## Rules

### R1: Repository Structure
1.1 Every repo MUST contain a README.md documenting purpose, setup, and maintainer.
1.2 Docker Compose repos MUST include a docker-compose.yml at the repository root.
1.3 PM2-managed repos MUST include an ecosystem.config.js or reference the ecosystem file.
1.4 nginx configs MUST be stored in a dedicated /nginx directory within the repo.
1.5 Secrets MUST NOT be committed; all secrets reference environment variables or Vault paths.

### R2: Service Definitions
2.1 Every service MUST declare its port bindings explicitly. Docker services MUST bind to 127.0.0.1 only.
2.2 Every service MUST declare dependencies (PostgreSQL, Redis, MinIO, Temporal) in a DEPENDENCIES.md.
2.3 Tailscale-only services MUST document mesh access requirements in a NETWORKING.md file.

### R3: Health Checks
3.1 Every long-running service MUST include a HEALTHCHECK (Docker) or health endpoint (PM2/HTTP).
3.2 Health endpoints MUST respond within 5 seconds and return HTTP 200 or 204.
3.3 Every service MUST declare its resource limits (CPU, memory) in the compose or config file.

## Enforcement Mechanism
Automated CI gate (repo-router-arch-check) runs against every submission. Manual review by the Architecture Review Board for any failed check. A submission failing R1-R3 SHALL NOT advance beyond PHASE-01 without an approved exception.

## Exception Process
Written justification submitted via GitHub issue with label `arch-policy-exception`. Exceptions expire after 90 days. ARB approves or denies within 5 business days.

## Audit Trail Requirements
All submission compliance status recorded in Repo Router database. Exception approvals logged with timestamp, approver, and expiration date. Monthly compliance reports generated. Non-compliant deployments flagged in Drift Detection Dashboard (PHASE-14).
