# PHASE-07: Sandbox Deployment Policy

## Policy Name
Sandbox Isolation and Deployment Policy

## Purpose
Define the requirements for deploying repos into an isolated sandbox environment. The sandbox is the first live deployment environment and MUST be fully isolated from production systems.

## Scope
Applies to all repos during PHASE-07 of the pipeline. Covers sandbox deployment on any Wheeler node:
- AI Ops Node sandbox namespace
- Hostinger Node sandbox namespace
- Core-DB Node sandbox databases and queues

## Rules

### R1: Isolation Requirements
1.1 Sandbox containers MUST run on a dedicated Docker network separate from staging and production.
1.2 Sandbox databases MUST use isolated databases with the `_sandbox` suffix.
1.3 Sandbox services MUST NOT access production Redis, PostgreSQL, or MinIO instances.
1.4 Sandbox DNS records MUST use a `-sandbox` subdomain suffix.

### R2: Resource Constraints
2.1 Sandbox containers MUST have CPU and memory limits at 50% of staging limits.
2.2 Sandbox deployments MUST expire after 72 hours unless explicitly extended.
2.3 No persistent storage in sandbox; all state is ephemeral and destroyed on teardown.

### R3: Network Access
3.1 Sandbox services MUST NOT be accessible from the public internet.
3.2 Sandbox access is restricted to Tailscale mesh or VPN only.
3.3 Sandbox monitoring is read-only; no alerting pages for sandbox issues.

## Enforcement Mechanism
Docker Compose project isolation with `COMPOSE_PROJECT_NAME=sandbox-<repo-name>`. Automated teardown runs every 72 hours. Isolated network verified by the sandbox-gate CI step.

## Exception Process
Extended sandbox lifetimes require operator approval and a documented reason. Long-lived sandboxes are reviewed weekly.

## Audit Trail Requirements
Sandbox creation and teardown events are logged. Resource usage is tracked. Sandbox lifespan and extension history are recorded in the Repo Router database.
