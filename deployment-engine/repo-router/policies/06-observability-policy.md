# PHASE-09: Observability Setup Policy

## Policy Name
Monitoring, Logging, and Observability Standards Policy

## Purpose
Establish mandatory observability standards for all services deployed through the Repo Router pipeline. Every service must expose metrics, ship logs, and define alerts before entering production.

## Scope
Applies to all repos reaching PHASE-09 across all Wheeler nodes:
- AI Ops Node metrics, logs, and alerts
- Hostinger Node metrics, logs, and alerts
- Core-DB Node infrastructure monitoring

## Rules

### R1: Metrics
1.1 Every service MUST expose Prometheus-compatible metrics on a `/metrics` endpoint.
1.2 Every service MUST record request count, latency (p50/p95/p99), error rate, and uptime.
1.3 System metrics (CPU, memory, disk, network) MUST be collected via node_exporter.
1.4 Metrics retention MUST be at least 30 days for Prometheus data.

### R2: Logging
2.1 Every service MUST log to stdout/stderr in structured JSON format.
2.2 Logs MUST include timestamp, severity level, service name, request ID, and message.
2.3 Centralized log aggregation (Loki, SigNoz, or equivalent) MUST be configured.
2.4 Log retention MUST be at least 90 days for production services.

### R3: Alerting
3.1 Every service MUST define at least three SLO-based alerts: High error rate (>5%), Service down, High latency (p99 > 2s).
3.2 Alerts MUST route to the Wheeler operations channel with severity labels.
3.3 Critical alerts MUST have an auto-escalation path if unacknowledged for 15 minutes.
3.4 Alert fatigue MUST be managed; no alert fires more than once per hour for the same condition.

### R4: Dashboards
4.1 Every service MUST have a Grafana dashboard showing health, latency, error rate, and throughput.
4.2 Dashboards MUST be version-controlled in the repo under a `/monitoring` directory.

## Enforcement Mechanism
Automated observability check (repo-router-obs-check) verifies metrics endpoint, log format, and alert definitions. Services without metrics endpoints fail the check and cannot advance.

## Exception Process
Observability exemptions require engineering lead approval. Temporary exemptions for legacy services expire in 30 days.

## Audit Trail Requirements
Observability coverage is tracked per service. Alert configuration changes are logged. Monthly observability compliance reports published.
