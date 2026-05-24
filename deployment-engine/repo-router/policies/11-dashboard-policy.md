# PHASE-14: Dashboard Policy

## Policy Name
Pipeline Dashboard and Visibility Requirements Policy

## Purpose
Define the visualization, reporting, and dashboard requirements for the entire Repo Router pipeline. All pipeline activity must be visible through dashboards accessible to operators and stakeholders.

## Scope
Applies to the Repo Router engine itself and all repos traversing the pipeline. Covers dashboards for pipeline status, deployment health, and operational visibility across all Wheeler nodes.

## Rules

### R1: Pipeline Dashboard
1.1 A live pipeline dashboard MUST display the current status of every repo in the pipeline, organized by phase.
1.2 Each repo card MUST show: repo name, current phase, phase status (passed, failed, in-progress, blocked), risk score, and time in phase.
1.3 The dashboard MUST update within 30 seconds of any pipeline state change.
1.4 Failed phases MUST display the specific check that failed and a link to logs.

### R2: Deployment Health Dashboard
2.1 A Grafana dashboard MUST display the health of all production-deployed services.
2.2 The dashboard MUST show: service uptime, error rate, request latency (p50/p95/p99), and resource usage.
2.3 Deployment history MUST be shown as an annotation overlay on service health graphs.

### R3: Operational Dashboards
3.1 Drift detection dashboard showing drift events per service over time.
3.2 Risk score trend dashboard showing risk distribution across the ecosystem.
3.3 Compliance dashboard showing architecture, security, and observability compliance rates.

### R4: Access Control
4.1 Read-only view available to all contributors and reviewers.
4.2 Operator view includes phase override controls and deployment actions.
4.3 Admin view includes policy management and audit log access.

### R5: Dashboard Standards
5.1 All dashboards MUST load within 3 seconds.
5.2 All dashboards MUST be responsive (desktop and mobile).
5.3 All dashboards MUST include a link to the related policy documentation.

## Enforcement Mechanism
The pipeline dashboard is a core component of the Repo Router engine. The Grafana dashboards are deployed as part of the observability stack (PHASE-09). Dashboard availability is monitored by the observability stack itself.

## Exception Process
Dashboard coverage exceptions for legacy services expire in 30 days. New services must have dashboards before production deployment.

## Audit Trail Requirements
Dashboard viewership statistics tracked. All dashboard configuration changes version-controlled. Quarterly dashboard effectiveness reviews conducted.
