---
name: worker-routing-operator
description: "Worker/Data Node operations: Temporal workflows, PostgreSQL management, Redis management, MinIO storage, pipeline worker management, heavy compute job routing."
trigger: worker operator, worker node, data node, core db, worker operations, temporal, pipeline worker
---

# Skill: Worker Routing Operator

Operations guide for wheeler-core-db-01 — the Worker/Data Node.

## Worker Node Responsibilities

- **PostgreSQL**: Primary database (wheeler-postgres :5432)
- **Redis**: Cache and queue (wheeler-redis :6379)
- **MinIO**: Object storage (wheeler-minio :9000-9001)
- **Temporal**: Workflow engine (temporal-server, temporal-ui)
- **Monitoring**: Prometheus, Grafana, Loki
- **Pipeline**: Prediction radar workers, schedulers
- **Metrics**: Node exporter, Postgres exporter, Redis exporter

## Key Services

### PostgreSQL
```bash
docker ps --filter "name=wheeler-postgres" --format '{{.Status}}'
# Verify port binding: MUST be 127.0.0.1, NOT 0.0.0.0
ss -tulpn | grep 5432
# Check replication (if configured)
docker exec wheeler-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### Redis
```bash
docker ps --filter "name=wheeler-redis" --format '{{.Status}}'
# Verify port: 127.0.0.1:6379
ss -tulpn | grep 6379
# Ping
docker exec wheeler-redis redis-cli ping
```

### Temporal
```bash
docker ps --filter "name=temporal" --format 'table {{.Names}}\t{{.Status}}'
# UI: http://127.0.0.1:8080 (via Tailscale or SSH tunnel)
```

### MinIO
```bash
docker ps --filter "name=wheeler-minio" --format '{{.Status}}'
# Console: http://127.0.0.1:9001
```

## Worker Profile (Safe Subset)

The Worker gets a REDUCED capability profile:
- **Slash commands**: docker-health, pm2-health, db-lockdown, private-network, daily-health, audit, secrets-scan, rollback, ecosystem-map
- **Skills**: docker-health, database-lockdown, private-network-check, rollback-first, secrets-scan, incident-response
- **Agents**: docker-expert, database-rls-auditor, engineering-sre
- **MCP Profile**: Prod (read-only)
- **NO**: deploy, cost-control, production-readiness (these are for AI Ops)

## Safety Constraints

- Worker has NO deployment capability
- Worker can audit and report, not modify
- All write operations require AI Ops approval
- Database audit is read-only
- Port binding checks are passive (flag, don't fix)
- Secrets scan is audit-only

## Common Operations

| Operation | Command |
|-----------|---------|
| DB audit | `/db-lockdown` |
| Docker audit | `/docker-health` |
| Network check | `/private-network` |
| Daily health | `/daily-health` |
| Capability sync (pull) | `wheeler-capabilities-sync --pull aiops` |
| Backup DB | `pg_dump -h 127.0.0.1 -U postgres ...` |
