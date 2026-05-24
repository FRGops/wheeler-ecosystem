# PHASE-03: Governance Framework Policy

## Policy Name
Repository Governance Framework Policy

## Purpose
Establish the governance framework for decision-making, approval gates, and role-based access control across the entire Repo Router pipeline. This policy is the constitution for the deployment pipeline.

## Scope
Covers all repos, all phases (PHASE-01 through PHASE-14), and all actors (developers, operators, reviewers, maintainers) interacting with the Repo Router.

## Rules

### R1: Approval Gates
1.1 PHASE-04 (Architecture Review) requires signoff from at least one senior engineer.
1.2 PHASE-05 (Security Scan) requires signoff from the security lead.
1.3 PHASE-10 (Zero-Trust Validation) requires signoff from the infrastructure lead.
1.4 PHASE-12 (Production Readiness) requires signoff from both the engineering and operations leads.
1.5 No deployment reaches PHASE-13 without all upstream gates passing.

### R2: Role Definitions
2.1 Contributors: can submit repos and view pipeline status.
2.2 Reviewers: can approve/reject phases PHASE-01 through PHASE-06.
2.3 Operators: can execute phases PHASE-07 through PHASE-13.
2.4 Administrators: can override gates (with audit logging) and manage policies.

### R3: Change Control
3.1 All policy changes require a pull request and approval from at least two administrators.
3.2 Policy changes take effect at the start of the next pipeline run, not retroactively.
3.3 Emergency policy overrides require a post-action review within 24 hours.

## Enforcement Mechanism
RBAC enforced by the Repo Router engine using JWT tokens or Tailscale identity. Every pipeline action checks the actor role against the required role for that phase.

## Exception Process
Only administrators can grant temporary role elevation. Elevation is automatically revoked after 24 hours and logged.

## Audit Trail Requirements
All approvals, rejections, and role changes are logged with actor identity, timestamp, and phase. Monthly governance reviews are published to the Wheeler operations channel.
