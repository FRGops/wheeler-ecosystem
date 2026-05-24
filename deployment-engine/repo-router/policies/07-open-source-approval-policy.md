# PHASE-03: Open-Source Usage Approval Policy

## Policy Name
Open-Source Dependency Approval Policy

## Purpose
Govern the approval, tracking, and compliance of all open-source dependencies introduced through the repo pipeline. Ensures legal compliance, license compatibility, and supply-chain security.

## Scope
Applies to all open-source packages, libraries, containers, and tools pulled into any repo within the Wheeler ecosystem. Covers direct and transitive dependencies across all nodes.

## Rules

### R1: License Compliance
1.1 Every dependency MUST have an SPDX-identified open-source license.
1.2 GPL, AGPL, and SSPL licensed packages require legal review before approval.
1.3 MIT, Apache 2.0, BSD, and ISC licenses are auto-approved.
1.4 All licenses MUST be compatible with the Wheeler ecosystem's Apache 2.0 licensed codebase.

### R2: Supply-Chain Security
2.1 Every container image MUST be pulled from a verified registry (Docker Hub verified publisher, GitHub Container Registry, or ECR).
2.2 Images MUST have a pinned SHA256 digest, not a mutable tag.
2.3 npm/pip/go modules MUST have their checksums verified.
2.4 Critical severity CVEs in any dependency MUST be resolved before deployment.

### R3: Dependency Inventory
3.1 Every repo MUST maintain an SBOM (Software Bill of Materials) in SPDX or CycloneDX format.
3.2 The SBOM MUST be regenerated on every dependency change.
3.3 All dependencies MUST be recorded in the repo router dependency database.

### R4: Approval Tiers
4.1 Tier 1 (Auto-Approved): Common packages with permissive licenses and no known CVEs.
4.2 Tier 2 (Review Required): Packages with copyleft licenses or recent vulnerability history.
4.3 Tier 3 (Prohibited): Packages with GPLv3, SSPL, or known malware associations.

## Enforcement Mechanism
Automated SBOM generation and license scanning in the CI pipeline. Dependency check tools (Trivy, Snyk, or pip-audit) run on every submission. Blocking: any Tier 3 dependency or unresolved critical CVE blocks advancement.

## Exception Process
Tier 2 packages require security lead review. Tier 3 exceptions require CTO-level approval and are documented in a risk register.

## Audit Trail Requirements
SBOM snapshots stored per deployment. License scan results logged. CVE resolution tracked with timestamps. Quarterly open-source compliance reports published.
