# PHASE-06: Risk Scoring Policy

## Policy Name
Deployment Risk Scoring Methodology Policy

## Purpose
Define the quantitative and qualitative risk scoring methodology for every repo traversing the deployment pipeline. Risk scores determine deployment priority, approval requirements, and rollback preparedness.

## Scope
Applies to all repos during PHASE-06 across all Wheeler nodes including AI Ops, Hostinger, and Core-DB.

## Rules

### R1: Risk Dimensions
Every repo is scored across five dimensions on a scale of 1 (lowest risk) to 5 (highest risk):

1.1 Data Sensitivity (DS): Does the repo handle PII, financial data, or credentials?
    - 1 = No sensitive data, 3 = Internal business data, 5 = PII or financial transactions

1.2 Service Criticality (SC): What happens if the service goes down?
    - 1 = No external impact, 3 = Impacts internal tools, 5 = Revenue-critical or customer-facing

1.3 Deployment Complexity (DC): How complex is the deployment?
    - 1 = Single container, 3 = Multi-service with DB, 5 = Cross-node distributed system

1.4 Dependency Depth (DD): How many downstream consumers depend on this repo?
    - 1 = Zero consumers, 3 = 1-3 consumers, 5 = 5+ consumers or external integrations

1.5 Security Exposure (SE): What is the attack surface?
    - 1 = Internal-only, no auth, 3 = Internal with authentication, 5 = Internet-facing with auth

### R2: Score Calculation
2.1 Total Risk Score = DS + SC + DC + DD + SE (range: 5 to 25).
2.2 Low Risk: Score 5-10. Standard pipeline, single approval gate.
2.3 Medium Risk: Score 11-17. Requires two approvals, extended integration testing.
2.4 High Risk: Score 18-25. Requires all four approval gates, extended sandbox, mandatory rollback plan.

### R3: Scoring Rules
3.1 Automated scoring runs during PHASE-06 using static analysis and ecosystem map data.
3.2 Scores can be manually adjusted by the operator with documented justification.
3.3 Score changes trigger re-evaluation of all downstream phase requirements.

## Enforcement Mechanism
Risk scoring is computed by the Repo Router engine. The score is attached to the pipeline context and determines which approval gates and phase requirements apply. High-risk repos must pass additional checks in PHASE-08 and PHASE-10.

## Exception Process
Score adjustments require documented justification. Any score override is logged and reviewed in the monthly governance meeting.

## Audit Trail Requirements
Risk scores are recorded per pipeline run with dimension breakdowns. Score history is tracked for trend analysis. Monthly risk distribution reports generated.
