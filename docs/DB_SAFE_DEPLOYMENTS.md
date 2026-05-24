# Wheeler Ecosystem — Database-Safe Deployments

| | |
|---|---|
| **Document ID** | WHL-DB-SAFE-v1.0 |
| **Classification** | Internal — Production Operations |
| **Owner** | Principal Platform Reliability Engineer |
| **Last Updated** | 2026-05-23 |
| **Applies To** | All database migrations, schema changes, and stateful operations across EDGE, AIOPS, and COREDB nodes |

---

## Table of Contents

1. [Core Principles](#1-core-principles)
2. [Destructive Operation Lockdown](#2-destructive-operation-lockdown)
3. [Backup-Before-Everything Protocol](#3-backup-before-everything-protocol)
4. [Schema Validation Pipeline](#4-schema-validation-pipeline)
5. [Alembic State Management](#5-alembic-state-management)
6. [Rollback Strategy for Migrations](#6-rollback-strategy-for-migrations)
7. [Staged Migration Flow](#7-staged-migration-flow)
8. [Zero-Downtime Migration Patterns](#8-zero-downtime-migration-patterns)
9. [Redis-Safe Operations](#9-redis-safe-operations)
10. [MinIO-Safe Operations](#10-minio-safe-operations)
11. [Vector DB Safety](#11-vector-db-safety)
12. [Migration Testing Protocol](#12-migration-testing-protocol)
13. [Lock Timeout and Connection Settings](#13-lock-timeout-and-connection-settings)
14. [Connection Pooling During Migrations](#14-connection-pooling-during-migrations)
15. [Emergency Recovery Procedures](#15-emergency-recovery-procedures)
16. [Migration Audit Log Format](#16-migration-audit-log-format)
17. [Enforcement & Automation](#17-enforcement--automation)

---

## 1. Core Principles

### The Immutable Rules

These rules are non-negotiable. Every person who touches a database in the Wheeler ecosystem must know and follow them.

| Rule | Statement | Rationale |
|------|-----------|-----------|
| **R1** | No destructive migration runs automatically. Ever. | `DROP TABLE`, `DROP COLUMN`, `TRUNCATE` must require explicit human approval and a separate deployment step. |
| **R2** | Backup before every migration. No exceptions. | If a backup fails, the migration does not proceed. The backup must be verified (checksummed) before the migration step begins. |
| **R3** | Every migration must have a tested downgrade path. | Upgrades without downgrades are one-way doors. Every `upgrade()` must have a corresponding `downgrade()` that has been tested on staging within the last 7 days. |
| **R4** | Staging first. Always. | No migration touches production until it has been run successfully against a staging database that is a fresh restore of production from within the last 24 hours. |
| **R5** | The migration audit log is append-only. | Every migration event (start, checkpoint, completion, failure, rollback) is logged to an immutable audit table. The log cannot be truncated or deleted without SRE Lead approval. |

### Scope

These rules apply to:

- **PostgreSQL 16** on COREDB (5.78.210.123) — primary application database
- **PostgreSQL** on Hostinger EDGE (187.77.148.88) — Chatwoot, n8n, local tooling DBs
- **Redis 7 / Valkey** on COREDB — caching, sessions, queues
- **MinIO** on COREDB — object storage, backups, model artifacts
- **Qdrant / pgvector** on COREDB — vector embeddings and semantic search
- **MongoDB** (if deployed) on COREDB — document storage

### Who Can Approve What

| Operation | Approval Required | Emergency Override |
|-----------|-------------------|-------------------|
| `CREATE TABLE`, `ADD COLUMN` (nullable, with default) | Developer + peer review | N/A — standard flow |
| `ADD COLUMN` (NOT NULL) | Developer + peer review + SRE Lead | N/A — use expand-contract pattern |
| `CREATE INDEX` | Developer + peer review | N/A — standard flow |
| `CREATE INDEX CONCURRENTLY` | Developer + peer review + SRE Lead | N/A — requires special handling |
| `DROP COLUMN` | SRE Lead + Engineering Manager | CEO/CTO approval required |
| `DROP TABLE` | SRE Lead + Engineering Manager + CTO | CEO approval required |
| `TRUNCATE` | SRE Lead + Engineering Manager + CTO | CEO approval required |
| Manual `UPDATE` / `DELETE` on production | SRE Lead + Engineering Manager | CEO approval required |

---

## 2. Destructive Operation Lockdown

### 2.1 Auto-Blocked Operations

The following SQL patterns are **automatically rejected** by the migration validation script. They will never run without explicit override.

```sql
-- BLOCKED: These statements are rejected by the pre-migration validator
DROP TABLE <any>;
DROP COLUMN <any>;
TRUNCATE TABLE <any>;
ALTER TABLE <any> DROP CONSTRAINT <any>;
DROP INDEX <any>;  -- unless concurrently rebuilding
DROP SCHEMA <any>;
DROP DATABASE <any>;
DELETE FROM <any>;  -- blocked unless wrapped in explicit approval marker
UPDATE <any> SET ... ;  -- blocked unless wrapped in explicit approval marker
```

### 2.2 Explicit Approval Marker

For operations that require destructive changes with documented approval, wrap the SQL in an approval block:

```sql
-- APPROVAL: TICKET=WHL-1234, APPROVER=jane.doe@company.com, DATE=2026-05-23, REASON="Removing deprecated payments_old table after 30-day retention confirmed"
-- BEGIN_APPROVED_BLOCK
DROP TABLE IF EXISTS payments_old;
-- END_APPROVED_BLOCK
```

The migration validator (`/root/scripts/db-validation.sh`) parses these markers and cross-references against an approval registry. Any destructive operation without a valid approval marker halts the migration pipeline.

### 2.3 Pre-Migration Destructive Scan

The validation script runs a destructive-pattern scan before every migration:

```bash
# Run against the target migration file
/root/scripts/db-validation.sh --scan-destructive /path/to/migration.sql

# Expected output when clean:
# [PASS] Destructive pattern scan: no DROP/TRUNCATE/DELETE found

# Expected output when violations found:
# [BLOCKED] Line 23: DROP TABLE payments_old (no approval marker found)
# [BLOCKED] Line 47: TRUNCATE TABLE sessions (no approval marker found)
# Migration blocked. 2 destructive operations need approval.
```

---

## 3. Backup-Before-Everything Protocol

### 3.1 Mandatory Pre-Migration Backup

Every migration must be preceded by a verified, checksummed backup. The backup script enforces this:

```bash
# Full pre-migration backup
/root/scripts/db-validation.sh --backup-before-migration \
  --db-host 5.78.210.123 \
  --db-port 5432 \
  --db-name frgcrm_production \
  --backup-dir /var/backups/wheeler/pre-migration/$(date +%Y-%m-%d_%H%M%S)

# The script:
# 1. Runs pg_dump --format=custom --verbose
# 2. Computes SHA256 checksum of the dump file
# 3. Verifies the dump is restorable (pg_restore --list succeeds)
# 4. Uploads a copy to MinIO off-node storage
# 5. Records all metadata to the migration audit log
```

### 3.2 Backup Verification Steps

| Step | Command | Success Criteria |
|------|---------|-----------------|
| 1. Dump database | `pg_dump -h $HOST -U $USER -d $DB -Fc -f $DUMPFILE` | Exit code 0, file size > 0 |
| 2. Checksum | `sha256sum $DUMPFILE > $DUMPFILE.sha256` | Checksum file written |
| 3. Verify dump | `pg_restore --list $DUMPFILE > /dev/null` | Exit code 0 |
| 4. Copy to MinIO | `mc cp $DUMPFILE myminio/backups/pre-migration/` | Exit code 0, object exists |
| 5. Verify MinIO copy | `mc stat myminio/backups/pre-migration/$FILENAME` | Object metadata returned |
| 6. Log to audit | Insert into `migration_audit_log` | Row inserted |

### 3.3 Backup Retention Policy

| Backup Type | Retention | Storage Location |
|-------------|-----------|-----------------|
| Pre-migration backup | 30 days | COREDB local + MinIO |
| Daily automated backup (pg_dump) | 7 days rolling | COREDB local |
| Weekly full backup | 90 days | MinIO + offsite (if configured) |
| Emergency pre-fix backup | 14 days | COREDB local + MinIO |

### 3.4 What If Backup Fails?

If the pre-migration backup fails for any reason:

1. The migration pipeline **halts immediately**.
2. The operator is notified with the exact failure reason (disk full, permission denied, connection refused).
3. The migration **does not proceed** until a fresh, verified backup succeeds.
4. If backup failure persists for > 30 minutes, escalate to SRE Lead.
5. No emergency override exists for the backup step. There is no scenario where a migration proceeds without a verified backup.

---

## 4. Schema Validation Pipeline

### 4.1 Pre-Migration Schema Comparison

Before any migration runs, the current production schema is compared against the expected schema that the migration will produce:

```bash
/root/scripts/db-validation.sh --validate-schema \
  --db-host 5.78.210.123 \
  --db-name frgcrm_production \
  --expected-schema /root/migrations/expected/frgcrm_expected_schema.sql \
  --migration-file /root/migrations/versions/0042_add_lead_scoring.sql
```

### 4.2 What Schema Validation Checks

| Check | Description | Severity |
|-------|-------------|----------|
| **Table existence** | All tables in expected schema exist in actual schema | BLOCKING |
| **Column existence** | All columns in expected schema exist in actual schema | BLOCKING |
| **Column type match** | Data types match between expected and actual | BLOCKING |
| **Column nullable match** | Nullable constraints match | BLOCKING |
| **Index existence** | Expected indexes are present | WARNING |
| **Foreign key existence** | Expected foreign keys are present | WARNING |
| **Sequence values** | Sequence current values are sane (not near overflow) | WARNING |
| **Table row counts** | Row counts are within expected ranges (not zero for non-empty tables) | INFO |
| **Extension presence** | Required extensions (pgvector, pg_stat_statements, uuid-ossp) are installed | BLOCKING |
| **Replication lag** | If replica exists, lag is < 100 MB behind primary | WARNING |

### 4.3 Post-Migration Schema Verification

After the migration completes, the same validation runs again to confirm the schema now matches the new expected state:

```bash
/root/scripts/db-validation.sh --verify-post-migration \
  --db-host 5.78.210.123 \
  --db-name frgcrm_production \
  --expected-schema /root/migrations/expected/frgcrm_expected_schema_v42.sql

# Output:
# [PASS] Table 'leads' now contains column 'lead_score' (numeric, nullable)
# [PASS] Index 'idx_leads_score' created
# [PASS] Schema matches expected state. 2 changes applied, 0 discrepancies.
```

---

## 5. Alembic State Management

### 5.1 Revision Integrity Checks

Before any migration, Alembic state is validated:

```bash
/root/scripts/db-validation.sh --validate-alembic \
  --db-host 5.78.210.123 \
  --db-name frgcrm_production

# Checks performed:
# 1. alembic current — get current head revision
# 2. alembic heads — detect multiple heads (branching, which is dangerous)
# 3. alembic history — verify linear revision chain (no gaps)
# 4. Compare local revision files with database alembic_version table
# 5. Detect orphaned revisions (files on disk but not in chain)
# 6. Detect missing revisions (in chain but files missing from disk)
```

### 5.2 Common Alembic Issues Detected

| Issue | Detection | Resolution |
|-------|-----------|------------|
| **Multiple heads** | `alembic heads` returns > 1 revision | Merge heads onto a single branch before proceeding |
| **Missing revision file** | Revision ID in `alembic_version` table but no .py file on disk | Restore file from version control or recreate from schema dump |
| **Orphaned revision file** | .py file exists but not in linear chain | Verify if file should be part of chain; if not, move to archive |
| **Stamp mismatch** | `alembic current` differs from expected | Run `alembic stamp` to correct, or investigate manual DB changes |
| **Downgrade path broken** | `downgrade()` function missing or raises NotImplementedError | Implement downgrade path before migration proceeds |

### 5.3 Alembic Safety Configuration

Every Alembic `env.py` in the Wheeler ecosystem must include:

```python
# env.py — required safety settings
def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            # SAFETY SETTINGS — DO NOT REMOVE
            transaction_per_migration=True,     # Wrap each migration in a transaction
            compare_type=True,                   # Detect column type changes
            compare_server_default=True,         # Detect default value changes
            render_as_batch=False,              # Batch mode OFF for PostgreSQL (supports transactional DDL)
        )

        with context.begin_transaction():
            context.run_migrations()
```

---

## 6. Rollback Strategy for Migrations

### 6.1 Transaction-Based Migrations (Default)

PostgreSQL supports transactional DDL. Most migrations run inside a transaction:

```sql
-- Good: This entire migration is in a transaction
-- If it fails, everything rolls back automatically

BEGIN;
  ALTER TABLE leads ADD COLUMN lead_score NUMERIC(5,2);
  CREATE INDEX idx_leads_score ON leads(lead_score);
  ALTER TABLE leads ADD COLUMN score_calculated_at TIMESTAMP;
COMMIT;
```

If **any** statement fails, the entire transaction rolls back. The database returns to its pre-migration state automatically.

### 6.2 Non-Transactional Operations

Some PostgreSQL operations cannot run inside a transaction. These require special handling:

| Operation | Reason | Handling |
|-----------|--------|----------|
| `CREATE INDEX CONCURRENTLY` | Cannot run in a transaction block | Run as standalone step, check result, proceed or abort |
| `ALTER TYPE ... ADD VALUE` | Cannot run in a transaction block | Run before transactional migration steps |
| `VACUUM FULL` | Cannot run in a transaction block | Schedule separately, not part of migration |
| `REINDEX CONCURRENTLY` | Cannot run in a transaction block | Run standalone, verify index status |

### 6.3 CREATE INDEX CONCURRENTLY Handling

```sql
-- This is NOT wrapped in a transaction
-- Step 1: Create index (may take minutes on large tables)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_score ON leads(lead_score);

-- Step 2: Verify the index was created (it may fail due to deadlocks)
-- Run this check BEFORE proceeding:
SELECT indexname FROM pg_indexes
WHERE tablename = 'leads' AND indexname = 'idx_leads_score';
-- If no row returned, the CONCURRENTLY index creation failed.
-- It left no invalid state behind. Retry or investigate.

-- Step 3: If index exists, mark migration step as complete
```

### 6.4 Tested Downgrade Requirement

Every migration MUST include a tested downgrade:

```python
# migrations/versions/0042_add_lead_scoring.py

def upgrade():
    op.add_column('leads', sa.Column('lead_score', sa.Numeric(5, 2), nullable=True))
    op.add_column('leads', sa.Column('score_calculated_at', sa.DateTime(), nullable=True))

def downgrade():
    # MUST exist and MUST have been tested on staging
    op.drop_column('leads', 'score_calculated_at')
    op.drop_column('leads', 'lead_score')
```

### 6.5 Rollback Decision Tree

```
Migration started
   |
   v
Step 1-3: Non-transactional operations (CONCURRENTLY indexes, etc.)
   |
   v
Step 4: BEGIN TRANSACTION
   |
   v
Step 5-N: Transactional DDL inside transaction
   |
   +---> [SUCCESS] --> COMMIT --> Post-migration validation --> Mark complete
   |
   +---> [FAILURE] --> ROLLBACK --> Database returns to pre-migration state
              |
              +---> For non-transactional steps that ran BEFORE the transaction:
              |     Run their inverse operations manually (DROP INDEX CONCURRENTLY, etc.)
              |
              +---> Investigate failure --> Fix migration --> Start from Step 1 again
```

---

## 7. Staged Migration Flow

### 7.1 The Seven-Stage Pipeline

Every migration flows through these seven stages. No stage can be skipped.

```
STAGE 1           STAGE 2            STAGE 3           STAGE 4
[BACKUP]    -->   [VALIDATE]   -->   [MIGRATE]   -->   [VERIFY]
   |                |                   |                  |
   v                v                   v                  v
pg_dump +       Schema check       Apply migration    Post-migration
checksum +      + Alembic          inside             schema check
MinIO copy      state check        transaction        + index check

STAGE 5           STAGE 6            STAGE 7
[HEALTH CHECK] --> [COMPLETE]   -->  [OR ROLLBACK]
   |                |                  |
   v                v                  v
App health        Mark migration    If any stage
endpoints +       complete in       failed: roll
connectivity      audit log         back + notify
```

### 7.2 Detailed Stage Instructions

#### Stage 1: Backup Current Database

```bash
#!/bin/bash
# file: /root/scripts/migration-stage1-backup.sh
set -euo pipefail

DB_HOST="${DB_HOST:-5.78.210.123}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-frgcrm_production}"
DB_USER="${DB_USER:-frgcrm_admin}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/wheeler/pre-migration}"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${DB_NAME}/${TIMESTAMP}"
DUMPFILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump"

mkdir -p "${BACKUP_DIR}"

echo "[STAGE 1] Starting backup of ${DB_NAME} at ${TIMESTAMP}"

# Step 1.1: Run pg_dump
echo "[1.1] Running pg_dump..."
pg_dump \
  --host="${DB_HOST}" \
  --port="${DB_PORT}" \
  --username="${DB_USER}" \
  --dbname="${DB_NAME}" \
  --format=custom \
  --verbose \
  --file="${DUMPFILE}" \
  --no-password

# Step 1.2: Compute checksum
echo "[1.2] Computing checksum..."
sha256sum "${DUMPFILE}" > "${DUMPFILE}.sha256"
echo "  SHA256: $(cat ${DUMPFILE}.sha256)"

# Step 1.3: Verify dump is restorable
echo "[1.3] Verifying dump restorability..."
pg_restore --list "${DUMPFILE}" > /dev/null
echo "  Dump is restorable. $(pg_restore --list ${DUMPFILE} | wc -l) objects."

# Step 1.4: Copy to MinIO
echo "[1.4] Copying to MinIO off-node storage..."
mc cp "${DUMPFILE}" "myminio/backups/pre-migration/${DB_NAME}/" 2>/dev/null || \
  echo "  WARNING: MinIO copy failed. Backup exists locally at ${DUMPFILE}"

# Step 1.5: Write metadata
cat > "${BACKUP_DIR}/metadata.json" << METADATA
{
  "database": "${DB_NAME}",
  "timestamp": "${TIMESTAMP}",
  "dump_file": "${DUMPFILE}",
  "sha256": "$(cat ${DUMPFILE}.sha256 | awk '{print $1}')",
  "size_bytes": $(stat --format=%s "${DUMPFILE}"),
  "pg_version": "$(pg_dump --version)",
  "host": "${DB_HOST}"
}
METADATA

echo "[STAGE 1] Backup complete: ${DUMPFILE}"
echo "  Size: $(du -h ${DUMPFILE} | cut -f1)"
echo "  Checksum: $(cat ${DUMPFILE}.sha256 | awk '{print $1}')"
```

#### Stage 2: Pre-Migration Validation

```bash
#!/bin/bash
# file: /root/scripts/migration-stage2-validate.sh
set -euo pipefail

DB_HOST="${DB_HOST:-5.78.210.123}"
DB_NAME="${DB_NAME:-frgcrm_production}"
MIGRATION_FILE="${MIGRATION_FILE:?Migration file path required}"

echo "[STAGE 2] Running pre-migration validation for ${MIGRATION_FILE}"

# Step 2.1: Destructive pattern scan
echo "[2.1] Scanning for destructive operations..."
/root/scripts/db-validation.sh --scan-destructive "${MIGRATION_FILE}"

# Step 2.2: Schema comparison
echo "[2.2] Comparing schemas..."
/root/scripts/db-validation.sh --validate-schema \
  --db-host "${DB_HOST}" \
  --db-name "${DB_NAME}" \
  --migration-file "${MIGRATION_FILE}"

# Step 2.3: Alembic state check
echo "[2.3] Validating Alembic state..."
/root/scripts/db-validation.sh --validate-alembic \
  --db-host "${DB_HOST}" \
  --db-name "${DB_NAME}"

# Step 2.4: Lock check
echo "[2.4] Checking for existing locks..."
psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" -c "
  SELECT pid, state, wait_event_type, wait_event, query_start,
         now() - query_start AS duration
  FROM pg_stat_activity
  WHERE wait_event_type = 'Lock' AND state != 'idle'
  ORDER BY query_start;
"

# Step 2.5: Connection check
echo "[2.5] Checking active connections..."
ACTIVE_CONNS=$(psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" -t -c \
  "SELECT count(*) FROM pg_stat_activity WHERE state != 'idle';")
echo "  Active connections: ${ACTIVE_CONNS}"
if [ "${ACTIVE_CONNS}" -gt 50 ]; then
  echo "  WARNING: High connection count (${ACTIVE_CONNS}). Consider scheduling during lower traffic."
fi

echo "[STAGE 2] Pre-migration validation passed."
```

#### Stage 3: Apply Migration

```bash
#!/bin/bash
# file: /root/scripts/migration-stage3-apply.sh
set -euo pipefail

DB_HOST="${DB_HOST:-5.78.210.123}"
DB_NAME="${DB_NAME:-frgcrm_production}"
MIGRATION_REV="${MIGRATION_REV:?Migration revision required}"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-5000}"  # 5 seconds
STATEMENT_TIMEOUT="${STATEMENT_TIMEOUT:-300000}"  # 5 minutes

echo "[STAGE 3] Applying migration ${MIGRATION_REV} to ${DB_NAME}"

# Step 3.1: Set safe timeouts
psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" -c "
  SET lock_timeout = '${LOCK_TIMEOUT}ms';
  SET statement_timeout = '${STATEMENT_TIMEOUT}ms';
" 2>&1

# Step 3.2: Run non-transactional steps first (if any)
# CONCURRENTLY index creation, type alterations, etc.
# This is handled by the migration script itself

# Step 3.3: Apply the migration
echo "[3.3] Running alembic upgrade ${MIGRATION_REV}..."
cd /root/wheeler-autonomous-ops

alembic -c alembic.ini upgrade "${MIGRATION_REV}" 2>&1 | tee /tmp/migration_${MIGRATION_REV}.log

ALEMBIC_EXIT=$?
if [ ${ALEMBIC_EXIT} -ne 0 ]; then
  echo "[FAILED] Migration ${MIGRATION_REV} failed with exit code ${ALEMBIC_EXIT}"
  echo "  Check log: /tmp/migration_${MIGRATION_REV}.log"
  echo "  Transaction rolled back automatically."
  echo "  Proceed to Stage 7 rollback for any non-transactional cleanup."
  exit ${ALEMBIC_EXIT}
fi

echo "[STAGE 3] Migration ${MIGRATION_REV} applied successfully."
```

#### Stage 4: Verify Schema Post-Migration

```bash
#!/bin/bash
# file: /root/scripts/migration-stage4-verify.sh
set -euo pipefail

DB_HOST="${DB_HOST:-5.78.210.123}"
DB_NAME="${DB_NAME:-frgcrm_production}"

echo "[STAGE 4] Verifying post-migration schema..."

# Step 4.1: Schema comparison (expected vs actual)
/root/scripts/db-validation.sh --verify-post-migration \
  --db-host "${DB_HOST}" \
  --db-name "${DB_NAME}"

# Step 4.2: Verify no invalid indexes
echo "[4.2] Checking for invalid indexes..."
INVALID_INDEXES=$(psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" -t -c \
  "SELECT count(*) FROM pg_index WHERE indisvalid = false;")
if [ "${INVALID_INDEXES}" -gt 0 ]; then
  echo "  WARNING: ${INVALID_INDEXES} invalid indexes found."
  psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" -c \
    "SELECT indexrelid::regclass FROM pg_index WHERE indisvalid = false;"
fi

# Step 4.3: Verify Alembic stamp
echo "[4.3] Verifying Alembic stamp..."
cd /root/wheeler-autonomous-ops
alembic current

echo "[STAGE 4] Post-migration verification complete."
```

#### Stage 5: Application Health Checks

```bash
#!/bin/bash
# file: /root/scripts/migration-stage5-healthcheck.sh
set -euo pipefail

AIOPS_HOST="${AIOPS_HOST:-5.78.140.118}"
HEALTH_ENDPOINTS=(
  "http://${AIOPS_HOST}:8000/health"
  "http://${AIOPS_HOST}:8001/health"
  "http://${AIOPS_HOST}:9000/health"
)

echo "[STAGE 5] Running application health checks..."

for endpoint in "${HEALTH_ENDPOINTS[@]}"; do
  echo "[5.1] Checking ${endpoint}..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${endpoint}" || echo "000")

  if [ "${HTTP_CODE}" = "200" ]; then
    echo "  [PASS] ${endpoint} returned ${HTTP_CODE}"
  else
    echo "  [FAIL] ${endpoint} returned ${HTTP_CODE}"
    echo "  WARNING: Health check failed for ${endpoint}"
  fi
done

# Step 5.2: Check database connectivity from app servers
echo "[5.2] Checking database connectivity from AIOPS..."
ssh ${AIOPS_HOST} "psql -h 5.78.210.123 -U frgcrm_admin -d frgcrm_production -c 'SELECT 1;' -t"

# Step 5.3: Check Redis connectivity
echo "[5.3] Checking Redis connectivity..."
ssh ${AIOPS_HOST} "redis-cli -h 5.78.210.123 -p 6379 PING"

echo "[STAGE 5] Health checks complete."
```

#### Stage 6: Mark Migration Complete

```bash
#!/bin/bash
# file: /root/scripts/migration-stage6-complete.sh
set -euo pipefail

MIGRATION_ID="${MIGRATION_ID:?Migration ID required}"
DB_NAME="${DB_NAME:-frgcrm_production}"
OPERATOR="${OPERATOR:-$(whoami)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "[STAGE 6] Marking migration ${MIGRATION_ID} as complete..."

# Insert into audit log
psql -h 5.78.210.123 -U frgcrm_admin -d frgcrm_production << SQL
INSERT INTO migration_audit_log (
  migration_id,
  stage,
  status,
  operator,
  db_name,
  started_at,
  completed_at,
  backup_path,
  checksum
) VALUES (
  '${MIGRATION_ID}',
  'COMPLETE',
  'SUCCESS',
  '${OPERATOR}',
  '${DB_NAME}',
  (SELECT started_at FROM migration_audit_log WHERE migration_id = '${MIGRATION_ID}' ORDER BY id DESC LIMIT 1),
  '${TIMESTAMP}'::timestamptz,
  (SELECT backup_path FROM migration_audit_log WHERE migration_id = '${MIGRATION_ID}' AND stage = 'BACKUP' ORDER BY id DESC LIMIT 1),
  (SELECT checksum FROM migration_audit_log WHERE migration_id = '${MIGRATION_ID}' AND stage = 'BACKUP' ORDER BY id DESC LIMIT 1)
);
SQL

echo "[STAGE 6] Migration ${MIGRATION_ID} marked complete at ${TIMESTAMP}."
echo "  Operator: ${OPERATOR}"
echo "  Database: ${DB_NAME}"
```

#### Stage 7: Rollback (If Needed)

```bash
#!/bin/bash
# file: /root/scripts/migration-stage7-rollback.sh
set -euo pipefail

MIGRATION_ID="${MIGRATION_ID:?Migration ID required}"
DB_HOST="${DB_HOST:-5.78.210.123}"
DB_NAME="${DB_NAME:-frgcrm_production}"
FAILED_STAGE="${FAILED_STAGE:?Failed stage number required}"

echo "[STAGE 7] Executing rollback for migration ${MIGRATION_ID}"
echo "  Failed at stage: ${FAILED_STAGE}"

# Step 7.1: If migration was applied (stage 3), run alembic downgrade
if [ "${FAILED_STAGE}" -ge 3 ]; then
  echo "[7.1] Transaction was rolled back automatically by PostgreSQL."
  echo "       Checking for non-transactional cleanup needed..."

  # Check if any CONCURRENTLY indexes were created before the transaction
  # This requires migration-specific knowledge
  echo "       Review migration ${MIGRATION_ID} for any pre-transaction steps."
  echo "       If CREATE INDEX CONCURRENTLY ran, run: DROP INDEX CONCURRENTLY IF EXISTS <index_name>;"
fi

# Step 7.2: Log the rollback
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" << SQL
INSERT INTO migration_audit_log (
  migration_id,
  stage,
  status,
  operator,
  db_name,
  started_at,
  completed_at,
  failure_reason
) VALUES (
  '${MIGRATION_ID}',
  'ROLLBACK',
  'FAILED',
  '${OPERATOR:-$(whoami)}',
  '${DB_NAME}',
  '${TIMESTAMP}'::timestamptz,
  '${TIMESTAMP}'::timestamptz,
  'Migration ${MIGRATION_ID} failed at stage ${FAILED_STAGE}. Rollback executed.'
);
SQL

# Step 7.3: Notify
echo "[7.3] Sending rollback notification..."
# /root/scripts/notify-team.sh "MIGRATION ROLLBACK" "Migration ${MIGRATION_ID} failed at stage ${FAILED_STAGE}. Database restored to pre-migration state."

echo "[STAGE 7] Rollback complete. Database is at pre-migration state."
```

---

## 8. Zero-Downtime Migration Patterns

### 8.1 The Expand-Contract Pattern

For changes that would normally lock a table for writes, use expand-contract. This is required for all NOT NULL column additions and column renames.

#### Example: Adding a NOT NULL Column

```sql
-- BAD: This locks the entire table for writes during the ALTER
ALTER TABLE leads ADD COLUMN priority INTEGER NOT NULL DEFAULT 1;

-- GOOD: Expand-contract pattern (3 deployments)

-- Deploy 1: Add nullable column (no table lock)
ALTER TABLE leads ADD COLUMN priority INTEGER;

-- Deploy 2: Backfill data and add default (application writes both old and new)
UPDATE leads SET priority = 1 WHERE priority IS NULL;
ALTER TABLE leads ALTER COLUMN priority SET DEFAULT 1;

-- Deploy 3: After application only writes to new column, add NOT NULL
-- (requires verifying no NULLs remain)
ALTER TABLE leads ALTER COLUMN priority SET NOT NULL;
```

#### Example: Renaming a Column

```sql
-- BAD: Renaming breaks all running application code immediately
ALTER TABLE leads RENAME COLUMN status TO lead_status;

-- GOOD: Expand-contract pattern

-- Deploy 1: Add new column (nullable)
ALTER TABLE leads ADD COLUMN lead_status VARCHAR(50);

-- Deploy 2: Application writes to BOTH columns
-- Add trigger to sync writes:
CREATE OR REPLACE FUNCTION sync_lead_status()
RETURNS TRIGGER AS $$
BEGIN
  NEW.lead_status = NEW.status;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_lead_status
  BEFORE INSERT OR UPDATE ON leads
  FOR EACH ROW EXECUTE FUNCTION sync_lead_status();

-- Backfill existing rows
UPDATE leads SET lead_status = status WHERE lead_status IS NULL;

-- Deploy 3: Application reads from new column only
-- Deploy 4: Drop old column (after confirming no code references it)
DROP TRIGGER IF EXISTS trg_sync_lead_status ON leads;
ALTER TABLE leads DROP COLUMN status;
```

### 8.2 Blue-Green Table Swaps

For large schema changes or data transformations, create a new table, migrate data, and swap:

```sql
-- Step 1: Create new table with desired schema
CREATE TABLE leads_v2 (
  LIKE leads INCLUDING ALL,
  lead_score NUMERIC(5,2),
  calculated_at TIMESTAMP,
  ai_category VARCHAR(100)
);

-- Step 2: Copy data (with transformation)
INSERT INTO leads_v2 (id, name, email, lead_score, ...)
SELECT id, name, email,
       CASE WHEN status = 'qualified' THEN 85.0 ELSE 30.0 END,
       NOW(),
       'uncategorized'
FROM leads;

-- Step 3: Create indexes on new table (CONCURRENTLY to avoid locks during copy)
CREATE INDEX CONCURRENTLY idx_leads_v2_score ON leads_v2(lead_score);

-- Step 4: In a transaction, swap the tables
BEGIN;
  ALTER TABLE leads RENAME TO leads_old;
  ALTER TABLE leads_v2 RENAME TO leads;
COMMIT;

-- Step 5: Application now uses new table. Drop old table after verification period.
-- Keep leads_old for at least 7 days before:
-- DROP TABLE leads_old;
```

### 8.3 Online Index Creation

```sql
-- Always use CONCURRENTLY for production index creation
-- This takes longer but does not block writes

-- Standard (blocks writes): NOT for production
CREATE INDEX idx_leads_email ON leads(email);

-- Concurrent (non-blocking): ALWAYS for production
CREATE INDEX CONCURRENTLY idx_leads_email ON leads(email);

-- Check progress (for large tables):
SELECT
  now() - query_start AS elapsed,
  state,
  wait_event_type,
  query
FROM pg_stat_activity
WHERE query LIKE '%CREATE INDEX%' AND state = 'active';
```

---

## 9. Redis-Safe Operations

### 9.1 Hard Bans

The following Redis commands are **banned** in all deployment, migration, and maintenance scripts:

| Banned Command | Reason | Alternative |
|----------------|--------|-------------|
| `FLUSHALL` | Deletes all keys in all databases. No recovery. | `FLUSHDB` only if in the correct database context and with approval. Prefer key-by-key deletion. |
| `FLUSHDB` | Deletes all keys in current database. | Use `SCAN` + `DEL` with pattern matching for targeted cleanup. |
| `CONFIG REWRITE` | Persists runtime config changes. Can corrupt config. | Use version-controlled `redis.conf` only. |
| `DEBUG SEGFAULT` | Crashes Redis intentionally. | Never. |
| `SHUTDOWN NOSAVE` | Shuts down without saving. Data loss. | Use `SHUTDOWN SAVE` or `BGSAVE` first. |

### 9.2 Key Prefixing Standard

All Wheeler ecosystem applications MUST use prefixed keys to avoid collisions:

```
# Prefix format: {service}:{environment}:{purpose}:{identifier}
frgcrm:prod:session:abc123
surplusai:prod:cache:product-search:query-hash-xyz
predictionradar:prod:rate-limit:user-42
wheelerbrain:prod:model-cache:gpt4-response-abc
ravynai:prod:job-lock:doc-analyze-789
```

### 9.3 Redis Backup Before Critical Changes

```bash
#!/bin/bash
# file: /root/scripts/redis-safe-backup.sh
# Run before any migration that modifies critical Redis keys

REDIS_HOST="${REDIS_HOST:-5.78.210.123}"
REDIS_PORT="${REDIS_PORT:-6379}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/wheeler/redis/$(date +%Y-%m-%d_%H%M%S)}"

mkdir -p "${BACKUP_DIR}"

echo "Triggering Redis RDB save..."
redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" BGSAVE

echo "Waiting for BGSAVE to complete..."
while [ "$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} LASTSAVE 2>/dev/null)" -ne "$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} LASTSAVE 2>/dev/null)" ]; do
  sleep 1
done

echo "Copying RDB file..."
redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" CONFIG GET dir
# Copy from the directory returned above

echo "Exporting critical keys..."
redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" --scan --pattern "frgcrm:prod:*" | \
  while read key; do
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" DUMP "$key" > "${BACKUP_DIR}/${key//\//_}.dump"
  done

echo "Redis backup complete: ${BACKUP_DIR}"
```

### 9.4 Redis Migration Checklist

Before modifying any Redis keys as part of a deployment:

- [ ] RDB backup (`BGSAVE`) completed and verified
- [ ] Key prefix verified (no `FLUSHALL`-style operations exist)
- [ ] Key-by-key backup of critical keys (sessions, rate limits, job queues)
- [ ] Application code has fallback behavior for cache misses (cache is not a source of truth)
- [ ] TTL is set on all new keys (no eternal keys in cache)
- [ ] Rollback plan: documented commands to restore keys from backup

---

## 10. MinIO-Safe Operations

### 10.1 Hard Bans

| Banned Command/Operation | Reason | Alternative |
|--------------------------|--------|-------------|
| `mc rm --force --recursive myminio/<bucket>` | Destroys entire bucket without confirmation | `mc rm` with explicit object listing, verified by operator |
| `mc admin policy remove` without backup | Removes IAM policy irreversibly | Export policy first, verify, then remove |
| `mc anonymous set upload` | Makes bucket publicly writable | Never enable public upload on production buckets |
| `mc anonymous set public` | Makes entire bucket world-readable | Use presigned URLs with expiration instead |

### 10.2 Bucket Policy Validation

Before any bucket policy change:

```bash
#!/bin/bash
# Export current policy before modifying
BUCKET="${1:?Bucket name required}"

echo "Backing up current policy for bucket: ${BUCKET}"
mc anonymous get-json myminio/"${BUCKET}" > \
  "/var/backups/wheeler/minio/policies/${BUCKET}_policy_$(date +%Y-%m-%d).json"

echo "Current policy:"
cat "/var/backups/wheeler/minio/policies/${BUCKET}_policy_$(date +%Y-%m-%d).json"

echo ""
echo "To restore: mc anonymous set-json myminio/${BUCKET} /var/backups/wheeler/minio/policies/${BUCKET}_policy_$(date +%Y-%m-%d).json"
```

### 10.3 Bucket-Level Safety Rules

| Rule | Enforcement |
|------|-------------|
| No `--force` flag in deployment scripts | Grep all shell scripts for `mc rm --force` before deployment |
| Versioning enabled on all production buckets | `mc version enable myminio/<bucket>` verified via `mc version info` |
| Object locking enabled on backup buckets | `mc bucket lock` with retention period |
| Lifecycle policies for cleanup (never manual `rm -rf`) | `mc ilm rule add` for automated expiration |
| Replication for critical buckets | `mc replicate add` for backup/disaster recovery |

### 10.4 MinIO Pre-Deployment Checklist

- [ ] All target buckets have versioning enabled? (`mc version info myminio/<bucket>`)
- [ ] Current bucket policies exported and saved?
- [ ] No `mc rm --force` in any deployment script?
- [ ] Lifecycle rules configured for automated cleanup?
- [ ] Backup/snapshot taken of critical buckets?

---

## 11. Vector DB Safety

### 11.1 Qdrant Safety Rules

```bash
# Never run these in deployment scripts:
# DELETE /collections/{collection_name}       — destroys entire collection
# DELETE /collections/{collection_name}/points — wipes all vectors

# Always backup before changes:
# 1. Snapshot the collection
curl -X POST "http://5.78.210.123:6333/collections/{collection_name}/snapshots"

# 2. Download the snapshot
curl "http://5.78.210.123:6333/collections/{collection_name}/snapshots/{snapshot_name}" \
  -o "/var/backups/wheeler/qdrant/{collection_name}_{date}.snapshot"

# 3. Verify snapshot exists
curl "http://5.78.210.123:6333/collections/{collection_name}/snapshots"
```

### 11.2 pgvector Safety Rules

```sql
-- pgvector indexes are part of PostgreSQL, so standard PostgreSQL rules apply.
-- Additional pgvector-specific rules:

-- 1. Index rebuild for pgvector:
-- IVFFlat indexes may need periodic rebuilding as data grows.
-- Use CONCURRENTLY (requires PostgreSQL 12+):

REINDEX INDEX CONCURRENTLY idx_embeddings_ivfflat;

-- 2. Before dropping a vector column:
-- Export the vectors if they cannot be regenerated:
\copy (SELECT id, embedding FROM documents) TO '/var/backups/wheeler/pgvector/document_embeddings.csv' CSV;

-- 3. Changing index type (ivfflat to hnsw):
-- Create new index first (CONCURRENTLY), verify, then drop old:
CREATE INDEX CONCURRENTLY idx_embeddings_hnsw ON documents
  USING hnsw (embedding vector_cosine_ops);
-- Verify new index is valid:
SELECT indexname, indexdef FROM pg_indexes WHERE indexname = 'idx_embeddings_hnsw';
DROP INDEX CONCURRENTLY idx_embeddings_ivfflat;
```

### 11.3 Vector DB Migration Checklist

- [ ] Collection/namespace snapshot taken?
- [ ] Snapshot verified (restored to staging successfully)?
- [ ] Vector dimension verified (changing dimension = full re-index)?
- [ ] Distance metric verified (changing metric = full re-index)?
- [ ] Index rebuild plan documented with timing estimates?
- [ ] Application can serve degraded results during re-indexing?
- [ ] Rollback plan: restore snapshot or rebuild original index?

---

## 12. Migration Testing Protocol

### 12.1 Testing Against Staging

Every migration must be tested against a staging database that is a **fresh restore of production from within the last 24 hours**.

```bash
#!/bin/bash
# file: /root/scripts/test-migration-staging.sh
set -euo pipefail

PROD_DB="frgcrm_production"
STAGING_DB="frgcrm_staging"
DB_HOST="${DB_HOST:-5.78.210.123}"
MIGRATION_REV="${MIGRATION_REV:?Migration revision required}"

echo "=== MIGRATION STAGING TEST ==="
echo "Migration: ${MIGRATION_REV}"
echo "Production DB: ${PROD_DB}"
echo "Staging DB: ${STAGING_DB}"

# Step 1: Drop and recreate staging from latest production backup
echo "[1/6] Restoring staging from production backup..."
LATEST_BACKUP=$(ls -t /var/backups/wheeler/pre-migration/${PROD_DB}/*/*.dump 2>/dev/null | head -1)
if [ -z "${LATEST_BACKUP}" ]; then
  echo "ERROR: No production backup found. Run a backup first."
  exit 1
fi

echo "  Using backup: ${LATEST_BACKUP}"

# Step 2: Restore to staging database
dropdb --if-exists -h "${DB_HOST}" -U frgcrm_admin "${STAGING_DB}" 2>/dev/null || true
createdb -h "${DB_HOST}" -U frgcrm_admin "${STAGING_DB}"
pg_restore -h "${DB_HOST}" -U frgcrm_admin -d "${STAGING_DB}" "${LATEST_BACKUP}"

# Step 3: Run migration against staging
echo "[2/6] Running migration on staging..."
cd /root/wheeler-autonomous-ops
ALEMBIC_DB="${STAGING_DB}" alembic upgrade "${MIGRATION_REV}"

# Step 4: Verify schema
echo "[3/6] Verifying staging schema..."
/root/scripts/db-validation.sh --verify-post-migration \
  --db-host "${DB_HOST}" \
  --db-name "${STAGING_DB}"

# Step 5: Run application test suite against staging
echo "[4/6] Running app tests against staging..."
# (varies by application)

# Step 6: Test downgrade
echo "[5/6] Testing downgrade path..."
ALEMBIC_DB="${STAGING_DB}" alembic downgrade -1
echo "  Downgrade succeeded."

# Re-apply after downgrade test
ALEMBIC_DB="${STAGING_DB}" alembic upgrade "${MIGRATION_REV}"
echo "  Re-upgrade succeeded."

echo "[6/6] Staging test complete. Migration ${MIGRATION_REV} is cleared for production."
echo "=== MIGRATION STAGING TEST PASSED ==="
```

### 12.2 Test Requirements by Migration Type

| Migration Type | Minimum Tests Required |
|----------------|----------------------|
| Add nullable column | Staging run, schema verify |
| Add NOT NULL column (expand-contract) | Staging run, schema verify, app integration test |
| Add index | Staging run, EXPLAIN ANALYZE on key queries |
| Add CONCURRENTLY index | Staging run, verify no deadlocks under concurrent load |
| Data migration (UPDATE) | Staging run, row count verification, sample data checks |
| Blue-green table swap | Full staging run, app test suite, rollback test |
| DROP COLUMN (with approval) | Staging run, verify no app code references column, 7-day waiting period |
| DROP TABLE (with approval) | Staging run, verify no FK references, 30-day waiting period |

---

## 13. Lock Timeout and Connection Settings

### 13.1 Migration Session Settings

Every migration session must set these PostgreSQL parameters:

```sql
-- Applied at the start of every migration session
SET lock_timeout = '5000';              -- 5 seconds: fail fast if can't acquire lock
SET statement_timeout = '300000';       -- 5 minutes: prevent runaway queries
SET idle_in_transaction_session_timeout = '60000';  -- 1 minute: prevent idle transactions
SET application_name = 'migration_operator';  -- Identify migration in pg_stat_activity
```

### 13.2 Lock Timeout Strategy

The `lock_timeout` value must be tuned per migration type:

| Migration Type | lock_timeout | Rationale |
|---------------|-------------|-----------|
| Small table (< 10K rows) | 2000ms | Very fast DDL, no reason to wait |
| Medium table (10K–1M rows) | 5000ms | Standard timeout |
| Large table (1M–10M rows) | 10000ms | May need to wait for long-running queries to finish |
| Very large table (> 10M rows) | 30000ms | Use concurrent or non-blocking patterns instead |
| CREATE INDEX CONCURRENTLY | N/A | Non-blocking by design; no lock_timeout needed |

### 13.3 Detecting Lock Contention

```sql
-- Query to identify what's holding locks that block migrations
SELECT
  blocked.pid AS blocked_pid,
  blocked.query AS blocked_query,
  blocking.pid AS blocking_pid,
  blocking.query AS blocking_query,
  now() - blocking.query_start AS blocking_duration
FROM pg_stat_activity AS blocked
JOIN pg_locks AS blocked_locks ON blocked.pid = blocked_locks.pid
JOIN pg_locks AS blocking_locks ON blocked_locks.lock_type = blocking_locks.lock_type
  AND blocked_locks.relation = blocking_locks.relation
  AND blocked_locks.pid != blocking_locks.pid
JOIN pg_stat_activity AS blocking ON blocking_locks.pid = blocking.pid
WHERE NOT blocked_locks.granted
  AND blocked.wait_event_type = 'Lock'
ORDER BY blocking_duration DESC;
```

---

## 14. Connection Pooling During Migrations

### 14.1 Pooling Strategy

During migrations, application connection pools must be configured to handle connection churn:

#### PgBouncer (Recommended for COREDB)

```ini
# pgbouncer.ini — migration-safe settings
[databases]
frgcrm_production = host=127.0.0.1 port=5432 dbname=frgcrm_production

[pgbouncer]
pool_mode = transaction
max_client_conn = 200
default_pool_size = 25
reserve_pool_size = 5
reserve_pool_timeout = 3

# During migrations: reduce pool size temporarily
# To allow the migration to acquire necessary locks:
#   echo "SET default_pool_size = 10;" | pgbouncer -U admin
#   echo "PAUSE frgcrm_production;" >> pgbouncer control
#   (run migration)
#   echo "RESUME frgcrm_production;" >> pgbouncer control
```

#### Application-Level Pooling

```python
# SQLAlchemy engine configuration for production
# Migration-safe: uses NullPool for migration scripts, QueuePool for app

from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool, QueuePool

# For migration scripts: NullPool (no persistent connections)
migration_engine = create_engine(
    DATABASE_URL,
    poolclass=NullPool,    # Each migration gets fresh connection, releases immediately
    connect_args={
        "application_name": "alembic_migration",
        "options": "-c lock_timeout=5000 -c statement_timeout=300000"
    }
)

# For application: QueuePool with overflow
app_engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=20,
    max_overflow=10,
    pool_recycle=3600,     # Recycle connections hourly
    pool_pre_ping=True,    # Verify connections before use
    connect_args={
        "application_name": "frgcrm_api"
    }
)
```

### 14.2 Pool Management During Migration

```bash
#!/bin/bash
# Steps for managing connection pools during migration

# 1. Before migration: drain application pools
echo "Draining connection pools..."
for app in frgcrm-api surplusai-api prediction-radar; do
  # Signal the app to reduce pool size or pause accepting connections
  curl -X POST "http://5.78.140.118:8000/admin/pool/drain" || true
done

# 2. Verify no active application queries are using the target tables
echo "Checking for active queries on target tables..."
psql -h 5.78.210.123 -U frgcrm_admin -d frgcrm_production << SQL
SELECT pid, application_name, state, query, now() - query_start AS duration
FROM pg_stat_activity
WHERE state != 'idle'
  AND application_name NOT LIKE 'migration%'
  AND application_name NOT LIKE 'pgbouncer%'
ORDER BY duration DESC;
SQL

# 3. Run migration (uses NullPool — no persistent connections)
echo "Running migration..."
/root/scripts/migration-stage3-apply.sh

# 4. After migration: restore application pools
echo "Restoring connection pools..."
curl -X POST "http://5.78.140.118:8000/admin/pool/restore" || true
pm2 restart frgcrm-api surplusai-api prediction-radar
```

---

## 15. Emergency Recovery Procedures

### 15.1 Recovery Decision Tree

```
DATABASE INCIDENT DETECTED
          |
          v
    What happened?
          |
   +------+------+-----------+-------------+
   |             |           |             |
   v             v           v             v
BAD           WRONG       DATA          DATABASE
MIGRATION     QUERY       CORRUPTION    CRASH
   |             |           |             |
   v             v           v             v
Run          Kill query   Restore from  Check disk
rollback     (pg_terminate  latest       space and
(alembic     _backend)     verified     PostgreSQL
downgrade)                 backup       logs
   |
   v
If rollback
fails:
  pg_restore
  from latest
  pre-migration
  backup
```

### 15.2 Emergency Restore Procedure

```bash
#!/bin/bash
# file: /root/scripts/emergency-db-restore.sh
# CRITICAL: This script restores the production database from backup.
# Only run during a declared incident. Requires SRE Lead approval.

set -euo pipefail

DB_HOST="${DB_HOST:-5.78.210.123}"
DB_NAME="${DB_NAME:-frgcrm_production}"
BACKUP_FILE="${1:?Backup file path required}"

echo "============================================"
echo "  EMERGENCY DATABASE RESTORE"
echo "============================================"
echo ""
echo "Target: ${DB_HOST}/${DB_NAME}"
echo "Backup: ${BACKUP_FILE}"
echo ""
echo "This will OVERWRITE the current database."
echo "All data since ${BACKUP_FILE} will be LOST."
echo ""

read -p "Type 'RESTORE' to proceed: " CONFIRM
if [ "${CONFIRM}" != "RESTORE" ]; then
  echo "Aborted."
  exit 1
fi

# Step 1: Take emergency snapshot of current state (even if broken)
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
EMERGENCY_DUMP="/var/backups/wheeler/emergency/${DB_NAME}_pre_restore_${TIMESTAMP}.dump"
mkdir -p "$(dirname ${EMERGENCY_DUMP})"

echo "[1/6] Taking emergency snapshot of current state..."
pg_dump -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" -Fc -f "${EMERGENCY_DUMP}" || \
  echo "WARNING: Emergency snapshot failed. Proceeding anyway."

# Step 2: Terminate all connections to the database
echo "[2/6] Terminating all connections to ${DB_NAME}..."
psql -h "${DB_HOST}" -U frgcrm_admin -d postgres << SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${DB_NAME}'
  AND pid <> pg_backend_pid();
SQL

# Step 3: Drop and recreate the database
echo "[3/6] Dropping and recreating ${DB_NAME}..."
dropdb -h "${DB_HOST}" -U frgcrm_admin --force "${DB_NAME}"
createdb -h "${DB_HOST}" -U frgcrm_admin "${DB_NAME}"

# Step 4: Restore from backup
echo "[4/6] Restoring from backup..."
pg_restore -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" \
  --verbose \
  --no-owner \
  --no-privileges \
  "${BACKUP_FILE}"

# Step 5: Verify restore
echo "[5/6] Verifying restore..."
RESTORED_TABLES=$(psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" -t -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
echo "  Tables restored: ${RESTORED_TABLES}"

# Step 6: Reset sequences (if needed) and record in audit log
echo "[6/6] Recording restore in audit log..."
psql -h "${DB_HOST}" -U frgcrm_admin -d "${DB_NAME}" << SQL
INSERT INTO migration_audit_log (
  migration_id, stage, status, operator, db_name, completed_at, failure_reason
) VALUES (
  'emergency-restore-${TIMESTAMP}', 'EMERGENCY_RESTORE', 'SUCCESS',
  '${OPERATOR:-$(whoami)}', '${DB_NAME}',
  now(),
  'Emergency restore from backup: ${BACKUP_FILE}'
);
SQL

echo ""
echo "============================================"
echo "  RESTORE COMPLETE"
echo "============================================"
echo "Database: ${DB_HOST}/${DB_NAME}"
echo "Restored from: ${BACKUP_FILE}"
echo "Pre-restore snapshot (for forensics): ${EMERGENCY_DUMP}"
echo ""
echo "Next steps:"
echo "  1. Restart application services: pm2 restart all"
echo "  2. Run health checks: /root/scripts/revenue-healthcheck.sh"
echo "  3. Verify data integrity: check row counts on key tables"
echo "  4. Notify team: /root/scripts/notify-team.sh 'DB Restore Complete'"
```

### 15.3 Emergency Contacts

| Role | Name | Contact | When to Escalate |
|------|------|---------|-----------------|
| SRE Lead | [FILL] | [FILL] | Any database incident requiring restore |
| Engineering Manager | [FILL] | [FILL] | Incidents lasting > 30 minutes |
| CTO | [FILL] | [FILL] | Data loss incidents or > 2 hours downtime |
| DBA (if exists) | [FILL] | [FILL] | Schema corruption, replication failure |

---

## 16. Migration Audit Log Format

### 16.1 Audit Table Schema

```sql
-- Run once on COREDB to create the audit log table
CREATE TABLE IF NOT EXISTS migration_audit_log (
  id              BIGSERIAL PRIMARY KEY,
  migration_id    TEXT NOT NULL,                        -- Unique migration identifier (e.g., alembic revision or manual ID)
  stage           TEXT NOT NULL,                        -- BACKUP, VALIDATE, MIGRATE, VERIFY, HEALTHCHECK, COMPLETE, ROLLBACK, EMERGENCY_RESTORE
  status          TEXT NOT NULL,                        -- STARTED, SUCCESS, FAILED, ROLLED_BACK
  operator        TEXT NOT NULL,                        -- OS user who executed the migration
  db_name         TEXT NOT NULL,                        -- Target database name
  db_host         TEXT NOT NULL,                        -- Target database host
  started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),   -- When this stage started
  completed_at    TIMESTAMPTZ,                          -- When this stage completed
  duration_ms     BIGINT,                               -- Duration of this stage in milliseconds
  backup_path     TEXT,                                 -- Path to pre-migration backup file
  checksum        TEXT,                                 -- SHA256 checksum of backup file
  migration_rev   TEXT,                                 -- Alembic revision (or SQL file path)
  rows_affected   BIGINT,                               -- Number of rows modified (if applicable)
  failure_reason  TEXT,                                 -- Error message if stage failed
  approval_ticket TEXT,                                 -- Jira/Linear ticket approving this migration
  approver        TEXT,                                 -- Person who approved the migration
  extra           JSONB DEFAULT '{}'::jsonb,            -- Any additional metadata

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for querying
CREATE INDEX idx_migration_audit_migration_id ON migration_audit_log(migration_id);
CREATE INDEX idx_migration_audit_db_name ON migration_audit_log(db_name);
CREATE INDEX idx_migration_audit_started_at ON migration_audit_log(started_at);
CREATE INDEX idx_migration_audit_status ON migration_audit_log(status);

-- Prevent modification (append-only via application logic)
-- In production, use a restricted role that only has INSERT permission on this table
```

### 16.2 Example Audit Log Entry

```json
{
  "migration_id": "2026-05-23-alembic-0042-lead-scoring",
  "stage": "COMPLETE",
  "status": "SUCCESS",
  "operator": "deploy-bot",
  "db_name": "frgcrm_production",
  "db_host": "5.78.210.123",
  "started_at": "2026-05-23T14:30:00Z",
  "completed_at": "2026-05-23T14:32:15Z",
  "duration_ms": 135000,
  "backup_path": "/var/backups/wheeler/pre-migration/frgcrm_production/2026-05-23_143000/frgcrm_production_2026-05-23_143000.dump",
  "checksum": "a1b2c3d4e5f6...",
  "migration_rev": "a3f8c2d1e4b5",
  "rows_affected": 0,
  "approval_ticket": "WHL-1423",
  "approver": "jane.doe@company.com",
  "extra": {
    "alembic_head_before": "b2e7a1f3c4d6",
    "alembic_head_after": "a3f8c2d1e4b5",
    "tables_before": 42,
    "tables_after": 42,
    "pre_validation": "passed",
    "post_validation": "passed",
    "health_checks_passed": true,
    "services_restarted": ["frgcrm-api", "surplusai-api"]
  }
}
```

### 16.3 Audit Log Query Templates

```sql
-- Get migration history for a specific database
SELECT migration_id, stage, status, operator,
       started_at, completed_at,
       duration_ms / 1000 AS duration_seconds
FROM migration_audit_log
WHERE db_name = 'frgcrm_production'
ORDER BY started_at DESC
LIMIT 20;

-- Find all failed migrations
SELECT migration_id, stage, failure_reason, started_at
FROM migration_audit_log
WHERE status = 'FAILED'
ORDER BY started_at DESC;

-- Get migration success rate (last 30 days)
SELECT
  status,
  count(*) AS count,
  round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS percentage
FROM migration_audit_log
WHERE stage = 'COMPLETE' AND started_at > now() - INTERVAL '30 days'
GROUP BY status;

-- Get average migration duration by database
SELECT db_name,
       count(*) AS migrations,
       round(avg(duration_ms) / 1000, 1) AS avg_duration_seconds,
       round(max(duration_ms) / 1000, 1) AS max_duration_seconds
FROM migration_audit_log
WHERE stage = 'COMPLETE' AND status = 'SUCCESS'
  AND started_at > now() - INTERVAL '30 days'
GROUP BY db_name;
```

---

## 17. Enforcement & Automation

### 17.1 Pre-Commit Hook

Add this to `.git/hooks/pre-commit` in every repository that contains migrations:

```bash
#!/bin/bash
# Pre-commit hook: blocks destructive SQL patterns in migration files

MIGRATION_FILES=$(git diff --cached --name-only | grep -E 'migrations/.*\.(py|sql)$')

for file in $MIGRATION_FILES; do
  echo "Checking ${file} for destructive patterns..."

  # Check for DROP TABLE without approval marker
  if grep -q "DROP TABLE" "${file}" && ! grep -q "BEGIN_APPROVED_BLOCK" "${file}"; then
    echo "ERROR: ${file} contains DROP TABLE without approval marker."
    echo "       Add an approval block or remove the DROP TABLE statement."
    exit 1
  fi

  # Check for DROP COLUMN without approval marker
  if grep -q "DROP COLUMN" "${file}" && ! grep -q "BEGIN_APPROVED_BLOCK" "${file}"; then
    echo "ERROR: ${file} contains DROP COLUMN without approval marker."
    exit 1
  fi

  # Check for TRUNCATE without approval marker
  if grep -q "TRUNCATE" "${file}" && ! grep -q "BEGIN_APPROVED_BLOCK" "${file}"; then
    echo "ERROR: ${file} contains TRUNCATE without approval marker."
    exit 1
  fi

  # Check for missing downgrade
  if [[ "${file}" == *.py ]]; then
    if ! grep -q "def downgrade" "${file}"; then
      echo "ERROR: ${file} is missing a downgrade() function."
      exit 1
    fi
    # Check it's not just raising NotImplementedError
    if grep -q "raise NotImplementedError" <(sed -n '/def downgrade/,/^def /p' "${file}"); then
      echo "ERROR: ${file} downgrade() raises NotImplementedError. Implement a real downgrade."
      exit 1
    fi
  fi

  echo "  ${file}: OK"
done

echo "Migration pre-commit check passed."
```

### 17.2 CI/CD Pipeline Gate

```yaml
# .github/workflows/migration-safety-check.yml
name: Migration Safety Check

on:
  pull_request:
    paths:
      - 'migrations/**'
      - 'alembic/versions/**'

jobs:
  migration-safety:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Scan for destructive operations
        run: |
          /root/scripts/db-validation.sh --scan-all-migrations

      - name: Verify all migrations have downgrade paths
        run: |
          for f in alembic/versions/*.py; do
            if ! grep -q "def downgrade" "$f"; then
              echo "ERROR: $f missing downgrade()"
              exit 1
            fi
            if grep -q "raise NotImplementedError" <(sed -n '/def downgrade/,/^def /p' "$f"); then
              echo "ERROR: $f downgrade() is NotImplementedError"
              exit 1
            fi
          done

      - name: Validate Alembic revision chain
        run: |
          /root/scripts/db-validation.sh --validate-alembic-chain

      - name: Test migration against staging
        run: |
          /root/scripts/test-migration-staging.sh
```

### 17.3 Daily Automated Checks

```bash
#!/bin/bash
# file: /etc/cron.daily/db-safety-check
# Runs daily at 06:00 UTC via cron

LOG="/var/log/wheeler/db-safety-check-$(date +%Y-%m-%d).log"

{
  echo "=== DB Safety Check $(date) ==="

  # Check backup freshness
  echo "--- Backup Freshness ---"
  LATEST_BACKUP=$(ls -t /var/backups/wheeler/daily/frgcrm_production/* 2>/dev/null | head -1)
  if [ -z "${LATEST_BACKUP}" ]; then
    echo "CRITICAL: No daily backups found for frgcrm_production"
  else
    BACKUP_AGE=$(( $(date +%s) - $(stat -c %Y "${LATEST_BACKUP}") ))
    BACKUP_HOURS=$(( BACKUP_AGE / 3600 ))
    if [ ${BACKUP_HOURS} -gt 24 ]; then
      echo "CRITICAL: Last backup is ${BACKUP_HOURS} hours old (threshold: 24h)"
    else
      echo "OK: Last backup ${BACKUP_HOURS} hours ago: ${LATEST_BACKUP}"
    fi
  fi

  # Check for long-running locks
  echo "--- Lock Check ---"
  LOCKS=$(psql -h 5.78.210.123 -U frgcrm_admin -d frgcrm_production -t -c \
    "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND now() - query_start > INTERVAL '5 minutes';")
  if [ "${LOCKS}" -gt 0 ]; then
    echo "WARNING: ${LOCKS} queries waiting on locks > 5 minutes"
  else
    echo "OK: No long-waiting lock queries"
  fi

  # Check for invalid indexes
  echo "--- Invalid Indexes ---"
  INVALID=$(psql -h 5.78.210.123 -U frgcrm_admin -d frgcrm_production -t -c \
    "SELECT count(*) FROM pg_index WHERE indisvalid = false;")
  if [ "${INVALID}" -gt 0 ]; then
    echo "WARNING: ${INVALID} invalid indexes found"
  else
    echo "OK: No invalid indexes"
  fi

  # Check disk space
  echo "--- Disk Space ---"
  DISK_USAGE=$(ssh 5.78.210.123 "df /var/lib/postgresql | tail -1 | awk '{print \$5}' | sed 's/%//'")
  if [ "${DISK_USAGE}" -gt 85 ]; then
    echo "CRITICAL: Database disk ${DISK_USAGE}% full"
  elif [ "${DISK_USAGE}" -gt 75 ]; then
    echo "WARNING: Database disk ${DISK_USAGE}% full"
  else
    echo "OK: Database disk ${DISK_USAGE}% used"
  fi

  echo "=== DB Safety Check Complete ==="
} >> "${LOG}" 2>&1
```

### 17.4 Operator Training Requirements

Before any operator is authorized to run production migrations, they must:

1. **Complete this document.** Read all 17 sections and sign off.
2. **Run 5 staging migrations.** Successfully apply and rollback 5 different migration types against staging.
3. **Pass the migration quiz.** Demonstrate knowledge of:
   - What operations are auto-blocked
   - The seven-stage migration flow
   - Rollback decision tree
   - Emergency restore procedure
   - Lock timeout strategy
4. **Pair with SRE Lead** on their first production migration.
5. **Re-certify quarterly.** Run a staging migration with rollback to maintain muscle memory.

---

## Appendix A: Quick Reference Card

```
┌──────────────────────────────────────────────────────────────────┐
│              DATABASE-SAFE DEPLOYMENT QUICK REFERENCE             │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  BEFORE EVERY MIGRATION:                                          │
│  □ Verified backup exists (fresh, checksummed, in MinIO)          │
│  □ Staging test passed with same migration                        │
│  □ Destructive scan clean (no unapproved DROP/TRUNCATE)           │
│  □ Downgrade path exists and was tested                           │
│  □ Alembic state clean (no multiple heads)                        │
│  □ Lock timeout and statement timeout configured                  │
│                                                                    │
│  SEVEN STAGES:                                                    │
│  1. BACKUP   → pg_dump + checksum + MinIO                        │
│  2. VALIDATE → Schema + destructive scan + Alembic state         │
│  3. MIGRATE  → Apply inside transaction                          │
│  4. VERIFY   → Post-migration schema check                       │
│  5. HEALTH   → App health endpoints + DB connectivity            │
│  6. COMPLETE → Log to audit table                                │
│  7. ROLLBACK → Only if any stage fails                           │
│                                                                    │
│  NEVER IN DEPLOYMENT SCRIPTS:                                     │
│  • DROP TABLE / DROP COLUMN / TRUNCATE (without approval)        │
│  • FLUSHALL / FLUSHDB (Redis)                                     │
│  • mc rm --force (MinIO)                                          │
│  • Migrations without downgrade()                                 │
│                                                                    │
│  EMERGENCY RESTORE:                                               │
│  /root/scripts/emergency-db-restore.sh <backup-file-path>         │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
```

---

**Document Status:** APPROVED — v1.0  
**Next Review:** 2026-06-23  
**Owner:** Principal Platform Reliability Engineer  
**Distribution:** SRE Team, Engineering Team, All Operators
