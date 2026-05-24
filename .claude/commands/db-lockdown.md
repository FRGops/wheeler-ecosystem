# /db-lockdown — Database Security Lockdown Audit

Verify all PostgreSQL instances are properly locked down. Checks port bindings, authentication, and network exposure.

## Execution (ALL in parallel)

```bash
# 1. Port binding check (CRITICAL)
ss -tulpn 2>/dev/null | grep 5432
ss -tulpn 2>/dev/null | grep 5433
ss -tulpn 2>/dev/null | grep 5434
ss -tulpn 2>/dev/null | grep 5435

# 2. Docker PostgreSQL containers and their bindings
docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E '5432|5433|5434|5435|postgres'

# 3. pg_hba.conf audit on each PostgreSQL container
for container in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'postgres|db|pg'); do
  echo "=== $container pg_hba.conf ==="
  docker exec "$container" cat /var/lib/postgresql/data/pg_hba.conf 2>/dev/null | grep -v '^#' | grep -v '^$' || echo "  [Cannot read]"
done

# 4. Check for trust authentication (CRITICAL — no password required)
for container in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'postgres|db|pg'); do
  docker exec "$container" cat /var/lib/postgresql/data/pg_hba.conf 2>/dev/null | grep -i 'trust' && echo "  [CRITICAL] $container has trust auth!"
done

# 5. SSL check
for container in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'postgres|db|pg'); do
  docker exec "$container" psql -U postgres -c "SHOW ssl;" 2>/dev/null || echo "  [CHECK] $container — SSL status unknown"
done

# 6. Connection limit check
for container in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'postgres|db|pg'); do
  docker exec "$container" psql -U postgres -c "SHOW max_connections;" 2>/dev/null
done
```

## Security Baseline

| Check | Standard | Critical If |
|-------|----------|-------------|
| Port binding | 127.0.0.1 only | 0.0.0.0 binding |
| Auth method | scram-sha-256 or md5 | trust auth |
| SSL | On for external connections | Off on public-facing |
| Connection limit | Set and enforced | Unlimited |
| Firewall | UFW denies public DB ports | Public port open |

## Output Format

```
╔══════════════════════════════════════════════╗
║   Database Lockdown Audit — <timestamp>      ║
╚══════════════════════════════════════════════╝

POSTGRESQL INSTANCES: <N> found
──────────────────────────────────────────────
INSTANCE: <name/container>
  Port:    <binding> [PASS/FAIL — 127.0.0.1/0.0.0.0]
  Auth:    <method> [PASS/FAIL]
  SSL:     <status> [PASS/FAIL]
  Trust:   [NONE FOUND / FOUND — CRITICAL]

──────────────────────────────────────────────
OVERALL: [SECURE / NEEDS HARDENING / UNSAFE]
ACTION REQUIRED: <specific steps>
```
