# PHASE-11: Staging Promotion Policy

## Policy Name
Sandbox-to-Staging Promotion Criteria Policy

## Purpose
Define the mandatory criteria that a repo MUST satisfy to be promoted from the sandbox environment (PHASE-07) to the staging environment. Staging mirrors production and is the final validation environment before production readiness checks.

## Scope
Applies to all repos completing PHASE-07 through PHASE-10 and seeking promotion to staging. Covers all Wheeler nodes.

## Rules

### R1: Pre-Promotion Requirements
1.1 The repo MUST have completed at least 24 hours of continuous operation in sandbox without crash-looping.
1.2 All PHASE-05 (Security Scan) findings MUST be resolved or have an approved exception.
1.3 The PHASE-06 (Risk Score) MUST be computed and attached to the pipeline context.
1.4 All PHASE-08 (Integration Tests) MUST pass at 100% success rate.
1.5 All PHASE-09 (Observability) checks MUST pass with metrics and logs flowing.
1.6 All PHASE-10 (Zero-Trust) checks MUST pass.

### R2: Staging Environment Requirements
2.1 Staging MUST use infrastructure (Docker, PM2, nginx) mirroring the production configuration.
2.2 Staging databases MUST be separate instances from production with the `_staging` suffix.
2.3 Staging DNS MUST use a `-staging` subdomain suffix.
2.4 Staging MUST run the same container image tag or PM2 version as intended for production.

### R3: Integration Validation
3.1 Staging services MUST prove they can communicate with their upstream dependencies.
3.2 Downstream consumers in staging MUST confirm no breaking API changes.
3.3 Database migrations MUST run successfully in staging before production consideration.

### R4: Promotion Gate
4.1 Promotion from sandbox to staging requires operator approval.
4.2 Approval is logged with identity, timestamp, and any caveats.
4.3 Promotion is executed by the Repo Router engine, not manually.

## Enforcement Mechanism
The Repo Router engine verifies all pre-promotion requirements before allowing promotion. The pipeline blocks at PHASE-11 until all checks pass. Manual promotion is not possible; all promotions go through the engine.

## Exception Process
Expedited promotion (skipping sandbox duration) requires engineering lead approval and is only permitted for low-risk (score 5-10) repos. The reason for expedited promotion is documented in the audit trail.

## Audit Trail Requirements
All promotion attempts are logged with pass/fail status for each requirement. Time spent in sandbox is recorded. Staging promotion history is maintained per repo.
