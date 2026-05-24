# PHASE-10: Zero-Trust Validation Policy

## Policy Name
Zero-Trust Security Validation Policy

## Purpose
Enforce zero-trust principles across the Wheeler deployment pipeline. Every service, connection, and access request is verified before deployment proceeds. This policy governs PHASE-10 of the pipeline.

## Scope
Applies to every service and repo that reaches PHASE-10 of the pipeline, across all Wheeler nodes:
- AI Ops Node (frgcrm, wheeler-revenue-automation, openclaw-dashboard)
- Hostinger Node (fundsrecoverygroup, frgops-surplusai, private-ai)
- Core-DB Node (all database and message queue services)

## Rules

### R1: Network Security
1.1 All inter-service communication MUST use mTLS or Tailscale mesh. No service communicates over open TCP.
1.2 Every Docker container MUST bind to 127.0.0.1 unless a documented exception exists.
1.3 UFW rules MUST deny all inbound traffic except on explicitly permitted ports.
1.4 Split-horizon DNS or Tailscale MagicDNS MUST be used for all internal service discovery.

### R2: Authentication and Authorization
2.1 Every HTTP endpoint MUST enforce authentication (basic auth, OAuth, or API key).
2.2 Every dashboard MUST be behind nginx basic auth at minimum.
2.3 Service accounts MUST use rotated credentials. Default passwords are forbidden.
2.4 JWT tokens, if used, MUST have an expiry of 24 hours or less for human users.

### R3: TLS and Encryption
3.1 All public-facing endpoints MUST terminate TLS (Let's Encrypt or internal CA).
3.2 All database connections (PostgreSQL, Redis) MUST use TLS or Tailscale encryption.
3.3 Secrets at rest MUST be encrypted. Environment variables containing secrets MUST be loaded at runtime only.

### R4: Audit and Logging
4.1 All authentication failures MUST be logged with source IP and timestamp.
4.2 All privilege escalations MUST be logged and alerted on.
4.3 Logs MUST be shipped to a centralized observability platform (PHASE-09).

## Enforcement Mechanism
Automated scanning with repo-router-zt-check runs against all services. Fails the pipeline if any service is found listening on 0.0.0.0, lacks auth, or uses default credentials. Zero-trust validation is a hard gate blocking PHASE-11 promotion.

## Exception Process
Zero-trust exceptions require signoff from the infrastructure lead and the security lead. Exceptions are reviewed weekly. No exception lasts longer than 30 days without re-approval.

## Audit Trail Requirements
All zero-trust scan results are stored per deployment attempt. Failed checks are logged with remediation guidance. Compliance trend reports are generated monthly.
