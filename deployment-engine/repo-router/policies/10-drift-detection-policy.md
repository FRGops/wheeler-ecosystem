# PHASE-14: Drift Detection Policy

## Policy Name
Configuration Drift Detection and Remediation Policy

## Purpose
Define the post-deployment monitoring requirements for detecting configuration drift between the deployed state and the declared state in version control. Drift detection is the final phase (PHASE-14) of the pipeline and runs continuously after deployment.

## Scope
Applies to all repos and services deployed through the Repo Router pipeline. Drift detection runs across all Wheeler nodes: AI Ops, Hostinger, and Core-DB.

## Rules

### R1: Drift Detection Coverage
1.1 Every deployed service MUST have its runtime configuration compared against the repo declaration at least every 15 minutes.
1.2 The following dimensions are monitored for drift:
    1.2.1 Docker container image tags and environment variables
    1.2.2 PM2 process configuration and environment variables
    1.2.3 nginx configuration files
    1.2.4 UFW firewall rules
    1.2.5 Docker Compose service definitions (ports, networks, volumes)
    1.2.6 Environment variable values (excluding secrets)
    1.2.7 DNS and reverse proxy routing rules

### R2: Drift Classification
2.1 Informational Drift: Comment changes, whitespace, non-functional differences. Logged, no alert.
2.2 Warning Drift: Changed resource limits, updated image tags (non-breaking). Alert sent to operations channel.
2.3 Critical Drift: Exposed ports, disabled auth, removed health checks. Immediate alert and auto-remediation attempt.

### R3: Remediation
3.1 Critical drift triggers automatic reconciliation: the declared state from the repo is re-applied.
3.2 If auto-remediation fails twice consecutively, the service is quarantined and an incident is opened.
3.3 Manual drift (intentional out-of-band changes) MUST be documented within 1 hour or the change is reverted.

### R4: Exclusions
4.1 Runtime-only state (connection pools, cache contents) is not drift.
4.2 Dynamic DNS records with TTL-based updates are not drift within tolerance.

## Enforcement Mechanism
Drift detection runs as a scheduled job within the Repo Router engine or as a sidecar service. Comparison uses SHA256 hashes of declared vs. deployed configuration. Critical drift auto-remediation uses the same deployment mechanism as PHASE-13.

## Exception Process
Temporary drift allowances (for emergency changes) require operator acknowledgment. Unexplained drift after 24 hours escalates to incident review.

## Audit Trail Requirements
Every drift event is logged with before/after diff, classification, and resolution. Drift frequency metrics are tracked per service. Monthly drift reports are published to the operations channel.
