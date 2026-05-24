# PHASE-02: Ecosystem Mapping Policy

## Policy Name
Repository Discovery and Ecosystem Mapping Policy

## Purpose
Govern the discovery, verification, and mapping of all repos within the Wheeler ecosystem. Ensures every repo passing through the pipeline has a verified origin, correct remotes, and an accurate dependency topology.

## Scope
Applies to every repo submitted for deployment across all Wheeler nodes:
- AI Ops Node (frgcrm, wheeler-revenue-automation, openclaw-dashboard, wheeler-ecosystem)
- Hostinger Node (fundsrecoverygroup, frgops-surplusai, private-ai, changedetection, healthchecks)
- Core-DB Node (PostgreSQL configs, Redis configs, MinIO buckets, Temporal workflows)
- Any new repo introduced to the ecosystem

## Rules

### R1: Discovery and Verification
1.1 Every repo MUST have a verified remote origin. GitHub remotes are checked against the wheeler-ops GitHub organization.
1.2 Repos on Hostinger or AI Ops nodes MUST have documented deployment coordinates (server, path, port).
1.3 Private repos MUST confirm Tailscale or VPN connectivity before mapping.

### R2: Dependency Topology
2.1 The pipeline MUST produce an ecosystem dependency graph showing all repo-to-repo relationships.
2.2 Circular dependencies MUST be flagged and resolved before advancing beyond PHASE-02.
2.3 External service dependencies (PostgreSQL, Redis, MinIO) MUST be annotated with host and port.

### R3: Version and Branch Mapping
3.1 Every repo MUST declare which branch is deployed in each environment (production, staging, sandbox).
3.2 Git tags MUST follow semantic versioning for production deployments.
3.3 The ecosystem map MUST be updated on every deploy or repo addition.

## Enforcement Mechanism
Automated discovery runs as a CI step. The ecosystem map is regenerated on each pipeline execution. Any repo failing remote verification is quarantined and requires manual operator intervention.

## Exception Process
Unverified remotes require written approval from the infrastructure lead. Allowed only for air-gapped or legacy repos that cannot be migrated.

## Audit Trail Requirements
Every ecosystem map snapshot is versioned and stored in the Repo Router database. Remote verification results are logged with SHA fingerprints. Dependency graph changes are tracked in a changelog.
