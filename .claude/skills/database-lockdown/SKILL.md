---
name: database-lockdown
description: "PostgreSQL security hardening: verify 127.0.0.1 binding, check pg_hba.conf, verify no trust auth, check password policies, SSL verification, connection limits."
trigger: db lockdown, database lockdown, postgres security, lock down database, db security, pg audit, postgres audit
---

# Skill: Database Lockdown

PostgreSQL security hardening audit. Every PostgreSQL instance in the ecosystem must pass all checks.

## Security Baseline

### Check 1: Port Binding (CRITICAL)
```bash
# Every PostgreSQL port must be 127.0.0.1, never 0.0.0.0
ss -tulpn | grep -E '5432|5433|5434|5435'
docker ps --format '{{.Names}} {{.Ports}}' | grep -E '5432|5433|5434|5435'
```

### Check 2: Authentication (CRITICAL)
```bash
# NO trust auth entries allowed in pg_hba.conf
for c in $(docker ps --format '{{.Names}}' | grep -iE 'postgres|db|pg'); do
  echo "=== $c ==="
  docker exec "$c" cat /var/lib/postgresql/data/pg_hba.conf 2>/dev/null | grep -v '^#' | grep -v '^$'
done
```
Required: All entries must use `scram-sha-256` or `md5`. `trust` is a CRITICAL finding.

### Check 3: Password Policy
- Minimum password length enforced
- No default passwords (postgres/postgres, etc.)
- Service accounts use strong random passwords

### Check 4: SSL (for external connections)
```bash
for c in $(docker ps --format '{{.Names}}' | grep -iE 'postgres|db|pg'); do
  docker exec "$c" psql -U postgres -c "SHOW ssl;" 2>/dev/null
done
```

### Check 5: Connection Limits
```bash
for c in $(docker ps --format '{{.Names}}' | grep -iE 'postgres|db|pg'); do
  docker exec "$c" psql -U postgres -c "SHOW max_connections;" 2>/dev/null
done
```

### Check 6: Firewall
```bash
ufw status | grep -E '5432|5433|5434|5435'
```
Required: All PostgreSQL ports must be DENY for public interface.

## Lockdown Procedure

If a database fails any check:

1. **Port binding fix**: Recreate container with `-p 127.0.0.1:<host>:<container>` (never 0.0.0.0)
2. **Auth fix**: Update pg_hba.conf, replace `trust` with `scram-sha-256`, reload config
3. **Password fix**: `ALTER USER <user> WITH PASSWORD '<new-strong-password>';`
4. **SSL fix**: Enable SSL in postgresql.conf, provide certificates
5. **Firewall fix**: `ufw deny from any to any port 5432,5433,5434,5435`

## Output Format

```
DATABASE LOCKDOWN: <hostname>
──────────────────────────────────────
INSTANCES FOUND: <N>

INSTANCE: <name>
  Port:    <binding> [PASS/FAIL]
  Auth:    <method> [PASS/FAIL]
  Trust:   [NONE / FOUND — CRITICAL]
  SSL:     <on/off> [PASS/FAIL]
  Max Con: <N> [OK/HIGH]
  Firewall:[ALLOWED/DENIED] [PASS/FAIL]

──────────────────────────────────────
OVERALL: [SECURE / NEEDS HARDENING / UNSAFE]
```
